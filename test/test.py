import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge
import os
import itertools
from PIL import Image

@cocotb.test()
async def test_project(dut):
    CLOCK_PERIOD = 40  # 25.175 MHz (~40 ns)

    H_DISPLAY = 640
    H_FRONT   = 16
    H_SYNC    = 96
    H_BACK    = 48
    V_DISPLAY = 480
    V_FRONT   = 10
    V_SYNC    = 2
    V_BACK    = 33

    H_TOTAL = H_DISPLAY + H_FRONT + H_SYNC + H_BACK
    V_TOTAL = V_DISPLAY + V_FRONT + V_SYNC + V_BACK

    palette = [bytes(3)] * 256
    for r1, r0, g1, g0, b1, b0 in itertools.product(range(2), repeat=6):
        red   = 170 * r1 + 85 * r0
        green = 170 * g1 + 85 * g0
        blue  = 170 * b1 + 85 * b0
        color_index = b0 << 6 | g0 << 5 | r0 << 4 | b1 << 2 | g1 << 1 | r1 << 0
        for sync_bits in (0x00, 0x08, 0x80, 0x88):
            palette[color_index | sync_bits] = bytes((red, green, blue))

    # Start clock
    clock = Clock(dut.clk, CLOCK_PERIOD, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    # Synchronize to the start of a vertical frame (rising edge of vsync leaving sync pulse)
    # Wait until vsync goes low (active), then back high (inactive)
    while int(dut.uo_out.value[3]) == 1:
        await ClockCycles(dut.clk, 1)
    while int(dut.uo_out.value[3]) == 0:
        await ClockCycles(dut.clk, 1)

    # Wait through the vertical back porch lines to reach the first visible line
    await ClockCycles(dut.clk, V_BACK * H_TOTAL)

    # Capture 1 visible frame
    framebuffer = bytearray(V_DISPLAY * H_DISPLAY * 3)

    for j in range(V_DISPLAY):
        # Capture visible portion of line
        for i in range(H_DISPLAY):
            val = int(dut.uo_out.value)
            framebuffer[3 * (j * H_DISPLAY + i) : 3 * (j * H_DISPLAY + i) + 3] = palette[val]
            await ClockCycles(dut.clk, 1)

        # Skip horizontal front porch, hsync, and back porch
        await ClockCycles(dut.clk, H_FRONT + H_SYNC + H_BACK)

    os.makedirs("output", exist_ok=True)
    frame = Image.frombytes("RGB", (H_DISPLAY, V_DISPLAY), bytes(framebuffer))
    frame.save("output/frame0.png")

    dut._log.info("Frame captured successfully without assertion mismatch.")
