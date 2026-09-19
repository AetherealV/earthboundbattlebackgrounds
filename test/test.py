import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
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

    CAPTURE_FRAMES = 1

    H_SYNC_START = H_DISPLAY + H_FRONT
    H_SYNC_END   = H_SYNC_START + H_SYNC
    H_TOTAL      = H_SYNC_END + H_BACK
    V_SYNC_START = V_DISPLAY + V_FRONT
    V_SYNC_END   = V_SYNC_START + V_SYNC
    V_TOTAL      = V_SYNC_END + V_BACK

    palette = [bytes(3)] * 256
    for r1, r0, g1, g0, b1, b0 in itertools.product(range(2), repeat=6):
        red   = 170 * r1 + 85 * r0
        green = 170 * g1 + 85 * g0
        blue  = 170 * b1 + 85 * b0
        color_index = b0 << 6 | g0 << 5 | r0 << 4 | b1 << 2 | g1 << 1 | r1 << 0
        for sync_bits in (0x00, 0x08, 0x80, 0x88):
            palette[color_index | sync_bits] = bytes((red, green, blue))

    clock = Clock(dut.clk, CLOCK_PERIOD, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    async def capture_line(framebuffer, offset):
        for i in range(H_TOTAL):
            hsync = int(dut.uo_out.value[7])
            vsync = int(dut.uo_out.value[3])
            assert hsync == (0 if H_SYNC_START <= i < H_SYNC_END else 1), "Unexpected hsync pattern"
            assert vsync == 1, "Unexpected vsync pattern"
            if i < H_DISPLAY:
                framebuffer[offset + 3 * i : offset + 3 * i + 3] = palette[int(dut.uo_out.value)]
            await ClockCycles(dut.clk, 1)

    async def capture_frame(frame_num):
        framebuffer = bytearray(V_DISPLAY * H_DISPLAY * 3)
        for j in range(V_DISPLAY):
            await capture_line(framebuffer, 3 * j * H_DISPLAY)
        await ClockCycles(dut.clk, H_TOTAL * (V_TOTAL - V_DISPLAY))
        return Image.frombytes("RGB", (H_DISPLAY, V_DISPLAY), bytes(framebuffer))

    os.makedirs("output", exist_ok=True)
    for i in range(CAPTURE_FRAMES):
        frame = await capture_frame(i)
        frame.save(f"output/frame{i}.png")
