`default_nettype none

module tt_um_earthbound_battle_grounds (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when design is powered
    input  wire       clk,      // 25.175 MHz clock
    input  wire       rst_n     // active low reset
);

    // Unused bidirectional pins
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;
    wire _unused_ok = &{ena, ui_in[7:5], uio_in, 1'b0};

    // -------------------------------------------------------------
    // 1. VGA 640x480 @ 60 Hz Timing Generator
    // -------------------------------------------------------------
    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_BACK    = 48;
    localparam H_TOTAL   = 800;

    localparam V_VISIBLE = 480;
    localparam V_FRONT   = 10;
    localparam V_SYNC    = 2;
    localparam V_BACK    = 33;
    localparam V_TOTAL   = 525;

    reg [9:0] h_count;
    reg [9:0] v_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 10'd0;
                if (v_count == V_TOTAL - 1)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 1'b1;
            end else begin
                h_count <= h_count + 1'b1;
            end
        end
    end

    wire h_sync_active = (h_count >= (H_VISIBLE + H_FRONT)) && (h_count < (H_VISIBLE + H_FRONT + H_SYNC));
    wire v_sync_active = (v_count >= (V_VISIBLE + V_FRONT)) && (v_count < (V_VISIBLE + V_FRONT + V_SYNC));

    wire hsync = ~h_sync_active; // Active low
    wire vsync = ~v_sync_active; // Active low
    wire display_on = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);

    // -------------------------------------------------------------
    // 2. PK Rockin Animation & Timebase
    // -------------------------------------------------------------
    reg [7:0] frame_count;
    wire frame_tick = (h_count == 0) && (v_count == 0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            frame_count <= 8'd0;
        else if (frame_tick)
            frame_count <= frame_count + 1'b1;
    end

    // Speed modulation: default or boosted via ui_in[0]
    wire [7:0] anim_timer = ui_in[0] ? (frame_count << 1) : frame_count;

    // -------------------------------------------------------------
    // 3. Screen Centering & Coordinate Transforms
    // -------------------------------------------------------------
    wire [9:0] cx = (h_count >= 320) ? (h_count - 320) : (320 - h_count);
    wire [9:0] cy = (v_count >= 240) ? (v_count - 240) : (240 - v_count);

    // Pseudo-sine wave horizontal raster distortion:
    // Recreates the SNES HDMA wavy line-offset effect
    wire [5:0] wave_phase = v_count[6:1] + anim_timer[6:1];
    wire [4:0] wave_distort = wave_phase[5] ? (~wave_phase[4:0]) : wave_phase[4:0];

    // Ripple / Diamond expansion from center
    wire [9:0] manhattan_dist = cx + cy;
    wire [9:0] ring_pattern = manhattan_dist + {wave_distort, 2'b00} - {anim_timer, 2'b00};

    // Strobe / Inversion trigger (EarthBound battle strobe)
    wire strobe_on = (ui_in[1] & frame_count[3]) | (frame_count[5:0] == 6'd0);

    // -------------------------------------------------------------
    // 4. EarthBound PK Rockin Psychedelic Color Engine
    // -------------------------------------------------------------
    wire [4:0] pattern_val = ring_pattern[6:2] ^ {h_count[4], v_count[4]};
    wire [2:0] palette_sel = ui_in[4:2];

    reg [1:0] r, g, b;

    always @(*) begin
        case (palette_sel)
            // 3'b000: Classic PK Rockin Psychedelic Rainbow / Violet
            3'b000: begin
                r = pattern_val[4:3] + anim_timer[4:3];
                g = pattern_val[3:2] ^ anim_timer[3:2];
                b = ~pattern_val[4:3];
            end
            // 3'b001: Golden Radiant Flash
            3'b001: begin
                r = pattern_val[4:3] | pattern_val[2:1];
                g = pattern_val[4:3];
                b = pattern_val[1:0];
            end
            // 3'b010: Deep Cosmic Indigo / Cyan
            3'b010: begin
                r = pattern_val[1:0];
                g = pattern_val[3:2] + anim_timer[3:2];
                b = pattern_val[4:3] | 2'b01;
            end
            // 3'b011: Fire / Red Distortion
            3'b011: begin
                r = 2'b11;
                g = pattern_val[3:2];
                b = pattern_val[1:0] ^ anim_timer[3:2];
            end
            // Default: Alternate cycling
            default: begin
                r = pattern_val[4:3] + palette_sel[1:0];
                g = pattern_val[3:2] + anim_timer[4:3];
                b = pattern_val[2:1];
            end
        endcase

        // Apply battle strobe flash
        if (strobe_on) begin
            r = ~r;
            g = ~g;
            b = ~b;
        end
    end

    // -------------------------------------------------------------
    // 5. Output Assignment (TinyVGA PMOD Pinout)
    // -------------------------------------------------------------
    // uo_out = {HSync, B0, G0, R0, VSync, B1, G1, R1}
    wire [1:0] final_r = display_on ? r : 2'b00;
    wire [1:0] final_g = display_on ? g : 2'b00;
    wire [1:0] final_b = display_on ? b : 2'b00;

    assign uo_out = {
        hsync,
        final_b[0],
        final_g[0],
        final_r[0],
        vsync,
        final_b[1],
        final_g[1],
        final_r[1]
    };

endmodule
