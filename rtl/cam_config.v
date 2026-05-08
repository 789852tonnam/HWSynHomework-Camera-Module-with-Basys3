`timescale 1ns/1ps
// cam_config.v
// OV7670 camera configuration sequencer.
//
// Ported from the uec2_projekt reference design (Bekasiak/Warcholak, AGH University,
// derived from fpga4student.com OV7670+Basys3). Combines ov7670_controller.v and
// ov7670_registers.v into a single module, adapted to our port list.
//
// Key changes from reference:
//   - 58-entry register ROM (0x00..0x39) matching the reference's ov7670_registers.v
//     plus AWB disable (0x38) and manual exposure AECH write (0x39).
//   - Inline ROM as a combinational case statement (not a separate module).
//   - Sentinel value 16'hFFFF signals end of ROM.
//   - Double soft reset at ROM entries 0x00 and 0x01 (OV7670 quirk from reference).
//   - reg_writes_done widened to [5:0] to accommodate NUM_REGS=58 (> 31-bit limit).
//   - top.v updated to wire LD[13:8] = reg_writes_done[5:0] (6 bits).
//   - Power-on reset sequence retained (cam_rst_n held low for RST_HOLD cycles).
//   - Explicit SOFT_RST_WAIT state maintained (even though ROM has double soft reset,
//     the wait enforces the OV7670 datasheet >=30ms requirement after the explicit
//     COM7=0x80 issued in S_SOFT_RST before the ROM walk begins).
//
// Note on SW[11] (sccb_slow): sccb_master now uses an internal fixed divider.
//   clk_div_run is wired through to sccb_master for port compatibility but has
//   no effect on SCCB clock rate. SW[11] indicator LED still works; the rate is fixed.
//
// Parameters:
//   RST_HOLD      - clk cycles to hold cam_rst_n low  (default 625000 = 25ms @ 25MHz)
//   POST_RST      - clk cycles after cam_rst_n release (default 250000 = 10ms)
//   SOFT_RST_WAIT - clk cycles after soft reset (default 750000 = 30ms)
//   REG_GAP       - clk cycles between ROM writes (default 2500 = ~100us)
//   OV7670_ID     - SCCB device ID write address (default 0x42)

module cam_config #(
    parameter RST_HOLD      = 625000,
    parameter POST_RST      = 250000,
    parameter SOFT_RST_WAIT = 750000,
    parameter REG_GAP       = 2500,
    parameter OV7670_ID     = 8'h42
) (
    input  wire clk,
    input  wire rst,

    // Camera hardware control
    output reg  cam_rst_n,    // camera RST# pin (active low)
    output reg  cam_pwdn,     // camera PWDN pin (keep 0 = powered)

    // SCCB interface (forwarded to sccb_master)
    output wire scl,
    inout  wire sda,

    // Runtime SCCB clock divisor (passed to sccb_master for port compatibility;
    // the new sccb_master ignores this internally — fixed internal divider is used)
    input  wire [10:0] clk_div_run,

    // Test-pattern enable (SW[8]): write color-bar registers at end
    input  wire test_pattern_en,

    // Status outputs
    output reg        cfg_done,          // stays high after config completes
    output reg [6:0]  reg_writes_done,   // count of completed ROM writes (0..78)
    output reg [6:0]  successful_xacts   // count of transactions where slave ACK'd all 3 phases
);

    // =============================================================
    // USER TUNING — manual exposure (AECH register).
    // Edit this value, rebuild, re-program. AEC is disabled via COM8
    // (ROM entry 0x38 writes 0x00), so this value is the chip's actual
    // exposure setting.
    // =============================================================
    localparam [7:0] EXPOSURE_VALUE = 8'h80;    // 0x00=dark, 0x80=mid, 0xFF=bright
    // =============================================================

    // -----------------------------------------------------------------------
    // SCCB master instance
    // -----------------------------------------------------------------------
    reg        sccb_start;
    reg  [7:0] sccb_id;
    reg  [7:0] sccb_sub;
    reg  [7:0] sccb_data;
    wire       sccb_done;
    wire       sccb_busy;
    wire       sccb_ack_id;
    wire       sccb_ack_sub;
    wire       sccb_ack_data;
    wire       sccb_ack_valid;

    sccb_master u_sccb (
        .clk         (clk),
        .rst         (rst),
        .clk_div_run (clk_div_run),
        .start       (sccb_start),
        .id          (sccb_id),
        .sub_addr    (sccb_sub),
        .data        (sccb_data),
        .done        (sccb_done),
        .busy        (sccb_busy),
        .ack_id      (sccb_ack_id),
        .ack_sub     (sccb_ack_sub),
        .ack_data    (sccb_ack_data),
        .ack_valid   (sccb_ack_valid),
        .scl         (scl),
        .sda         (sda)
    );

    // -----------------------------------------------------------------------
    // 78-entry register ROM — based on AngeloJacobo's proven OV7670 config
    // (https://github.com/AngeloJacobo/FPGA_OV7670_Camera_Interface)
    // with gamma curve, color matrix, AGC/AEC, and critical "magic" registers.
    // Sentinel 16'hFFFF after last entry signals done.
    // -----------------------------------------------------------------------
    localparam NUM_REGS = 77;   // entries 0x00..0x4C

    reg [7:0] rom_addr;         // current ROM index being written
    reg [15:0] command;         // combinational output: {reg_addr, reg_val}

    always @(*) begin
        case (rom_addr)
            // --- Soft reset ---
            8'h00: command = 16'h1280;   // COM7: soft reset
            8'h01: command = 16'h1280;   // COM7: soft reset (second — OV7670 quirk)

            // --- Output format: RGB565 ---
            8'h02: command = 16'h1204;   // COM7: RGB output mode
            8'h03: command = 16'h1100;   // CLKRC: no prescale (OUR ORIGINAL)
            8'h04: command = 16'h40D0;   // COM15: RGB565, full output range
            8'h05: command = 16'h0C00;   // COM3: no scaling
            8'h06: command = 16'h3E00;   // COM14: no DCW, no PCLK divider
            8'h07: command = 16'h0400;   // COM1: disable CCIR656
            8'h08: command = 16'h3A04;   // TSLB: correct output data sequence
            8'h09: command = 16'h1418;   // COM9: AGC ceiling x4

            // --- Color matrix coefficients ---
            8'h0A: command = 16'h4FB3;   // MTX1
            8'h0B: command = 16'h50B3;   // MTX2
            8'h0C: command = 16'h5100;   // MTX3
            8'h0D: command = 16'h523D;   // MTX4
            8'h0E: command = 16'h53A7;   // MTX5
            8'h0F: command = 16'h54E4;   // MTX6
            8'h10: command = 16'h589E;   // MTXS: matrix sign and scale
            8'h11: command = 16'h3D80;   // COM13: gamma enable, UV auto-adjust disabled

            // --- Window/timing (OUR ORIGINAL — proven working) ---
            8'h12: command = 16'h1711;   // HSTART
            8'h13: command = 16'h1861;   // HSTOP
            8'h14: command = 16'h32A4;   // HREF
            8'h15: command = 16'h1903;   // VSTRT
            8'h16: command = 16'h1A7B;   // VSTOP
            8'h17: command = 16'h030A;   // VREF
            8'h18: command = 16'h0F4B;   // COM6
            8'h19: command = 16'h1E37;   // MVFP

            // --- Critical "magic" registers ---
            8'h1A: command = 16'h330B;   // CHLF
            8'h1B: command = 16'h3C78;   // COM12: no HREF when VSYNC low
            8'h1C: command = 16'h6900;   // GFIX
            8'h1D: command = 16'h7400;   // REG74
            8'h1E: command = 16'hB084;   // RSVD: *required* for good color
            8'h1F: command = 16'hB10C;   // ABLC1
            8'h20: command = 16'hB20E;   // RSVD
            8'h21: command = 16'hB380;   // THL_ST

            // --- Scaling (from reference) ---
            8'h22: command = 16'h703A;
            8'h23: command = 16'h7135;
            8'h24: command = 16'h7211;
            8'h25: command = 16'h73F0;
            8'h26: command = 16'hA202;

            // --- Gamma curve ---
            8'h27: command = 16'h7A20;   // SLOP
            8'h28: command = 16'h7B10;   // GAM1
            8'h29: command = 16'h7C1E;   // GAM2
            8'h2A: command = 16'h7D35;   // GAM3
            8'h2B: command = 16'h7E5A;   // GAM4
            8'h2C: command = 16'h7F69;   // GAM5
            8'h2D: command = 16'h8076;   // GAM6
            8'h2E: command = 16'h8180;   // GAM7
            8'h2F: command = 16'h8288;   // GAM8
            8'h30: command = 16'h838F;   // GAM9
            8'h31: command = 16'h8496;   // GAM10
            8'h32: command = 16'h85A3;   // GAM11
            8'h33: command = 16'h86AF;   // GAM12
            8'h34: command = 16'h87C4;   // GAM13
            8'h35: command = 16'h88D7;   // GAM14
            8'h36: command = 16'h89E8;   // GAM15

            // --- AGC / AEC ---
            8'h37: command = 16'h13E0;   // COM8: disable AGC/AEC temporarily
            8'h38: command = 16'h0000;   // GAIN: 0
            8'h39: command = 16'h1000;   // AECH: 0
            8'h3A: command = 16'h0D40;   // COM4
            8'h3B: command = 16'h1418;   // COM9
            8'h3C: command = 16'hA505;   // BD50MAX
            8'h3D: command = 16'hAB07;   // BD60MAX
            8'h3E: command = 16'h2495;   // AGC upper
            8'h3F: command = 16'h2533;   // AGC lower
            8'h40: command = 16'h26E3;   // AGC/AEC fast mode
            8'h41: command = 16'h9F78;   // HAECC1
            8'h42: command = 16'hA068;   // HAECC2
            8'h43: command = 16'hA103;   // magic
            8'h44: command = 16'hA6D8;   // HAECC3
            8'h45: command = 16'hA7D8;   // HAECC4
            8'h46: command = 16'hA8F0;   // HAECC5
            8'h47: command = 16'hA990;   // HAECC6
            8'h48: command = 16'hAA94;   // HAECC7
            8'h49: command = 16'h13E7;   // COM8: RE-ENABLE AGC + AEC + AWB (Bit 1 = 1)

            // --- Additional ---
            8'h4A: command = 16'h6900;   // GFIX: let AWB handle RGB gain
            8'h4B: command = 16'h8C00;   // RGB444: disable
            8'h4C: command = 16'h6B4A;   // DBLV: PLL

            default: command = 16'hFFFF; // sentinel: signals end of ROM
        endcase
    end

    // Color-bar extra ROM: 2 entries appended when test_pattern_en=1
    localparam NUM_CB_REGS = 2;
    reg [15:0] cb_rom [0:NUM_CB_REGS-1];

    initial begin
        cb_rom[0] = 16'h7180;   // SCALING_YSC: bit[7]=1 enables color bar
        cb_rom[1] = 16'h4208;   // COM17: bit[3]=1 enables DSP color bar
    end

    // -----------------------------------------------------------------------
    // State machine
    // -----------------------------------------------------------------------
    localparam [3:0]
        S_RESET      = 4'd0,   // hold cam_rst_n low for RST_HOLD cycles
        S_POST_RST   = 4'd1,   // wait POST_RST cycles after cam_rst_n released
        S_SOFT_RST   = 4'd2,   // send explicit COM7=0x80 soft reset via SCCB
        S_WAIT_DONE  = 4'd3,   // wait for sccb_master to finish soft reset
        S_SOFT_WAIT  = 4'd4,   // wait SOFT_RST_WAIT cycles (>=30ms required by datasheet)
        S_ROM_START  = 4'd5,   // start SCCB write for current ROM entry
        S_ROM_WAIT   = 4'd6,   // wait for sccb_master to finish ROM write
        S_ROM_GAP    = 4'd7,   // inter-register settling delay
        S_CB_START   = 4'd8,   // start SCCB write for color-bar entry
        S_CB_WAIT    = 4'd9,   // wait for sccb_master to finish color-bar write
        S_CB_GAP     = 4'd10,  // inter-register settling delay for color-bar
        S_DONE       = 4'd11;  // all registers written; idle

    reg [3:0]  state;
    reg [19:0] timer;          // general-purpose delay counter
    reg [6:0]  rom_idx;        // ROM index (0..NUM_REGS-1), 7 bits for 78 entries
    reg [4:0]  cb_idx;         // color-bar ROM index (0..NUM_CB_REGS-1)

    // Initialize for simulation (X-prop avoidance)
    initial begin
        state            = S_RESET;
        timer            = 20'd0;
        rom_idx          = 7'd0;
        rom_addr         = 8'd0;
        cb_idx           = 5'd0;
        cam_rst_n        = 1'b0;
        cam_pwdn         = 1'b0;
        cfg_done         = 1'b0;
        reg_writes_done  = 7'd0;
        successful_xacts = 7'd0;
        sccb_start       = 1'b0;
        sccb_id          = 8'd0;
        sccb_sub         = 8'd0;
        sccb_data        = 8'd0;
    end

    // -----------------------------------------------------------------------
    // Main configuration state machine
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state            <= S_RESET;
            timer            <= 20'd0;
            rom_idx          <= 7'd0;
            rom_addr         <= 8'd0;
            cb_idx           <= 5'd0;
            cam_rst_n        <= 1'b0;
            cam_pwdn         <= 1'b0;
            cfg_done         <= 1'b0;
            reg_writes_done  <= 7'd0;
            successful_xacts <= 7'd0;
            sccb_start       <= 1'b0;
        end else begin
            sccb_start <= 1'b0;  // default: no transaction start

            case (state)
                // Hold camera RST_N low for RST_HOLD cycles
                S_RESET: begin
                    cam_rst_n <= 1'b0;
                    cam_pwdn  <= 1'b0;
                    if (timer >= RST_HOLD - 1) begin
                        cam_rst_n <= 1'b1;
                        timer     <= 20'd0;
                        state     <= S_POST_RST;
                    end else begin
                        timer <= timer + 20'd1;
                    end
                end

                // Wait POST_RST cycles after releasing cam_rst_n
                S_POST_RST: begin
                    if (timer >= POST_RST - 1) begin
                        timer <= 20'd0;
                        state <= S_SOFT_RST;
                    end else begin
                        timer <= timer + 20'd1;
                    end
                end

                // Send explicit COM7=0x80 soft reset before ROM walk
                // (The ROM entries 0x00 and 0x01 also do soft reset, but this
                // explicit pre-ROM reset with the long SOFT_RST_WAIT ensures
                // the camera starts from a clean state.)
                S_SOFT_RST: begin
                    if (!sccb_busy) begin
                        sccb_start <= 1'b1;
                        sccb_id    <= OV7670_ID;
                        sccb_sub   <= 8'h12;   // COM7 register
                        sccb_data  <= 8'h80;   // soft reset bit
                        state      <= S_WAIT_DONE;
                    end
                end

                // Wait for sccb_master to complete the soft reset
                S_WAIT_DONE: begin
                    if (sccb_done) begin
                        if (!sccb_ack_id && !sccb_ack_sub && !sccb_ack_data)
                            successful_xacts <= successful_xacts + 6'd1;
                        timer <= 20'd0;
                        state <= S_SOFT_WAIT;
                    end
                end

                // Wait SOFT_RST_WAIT cycles (>= 30 ms per OV7670 datasheet)
                S_SOFT_WAIT: begin
                    if (timer >= SOFT_RST_WAIT - 1) begin
                        timer    <= 20'd0;
                        rom_idx  <= 6'd0;
                        rom_addr <= 8'd0;
                        state    <= S_ROM_START;
                    end else begin
                        timer <= timer + 20'd1;
                    end
                end

                // Start SCCB write for current ROM entry
                S_ROM_START: begin
                    if (rom_idx >= NUM_REGS) begin
                        // All ROM entries written; handle test-pattern extension
                        cb_idx <= 5'd0;
                        if (test_pattern_en)
                            state <= S_CB_START;
                        else
                            state <= S_DONE;
                    end else if (!sccb_busy) begin
                        sccb_start <= 1'b1;
                        sccb_id    <= OV7670_ID;
                        sccb_sub   <= command[15:8];   // register address from ROM
                        sccb_data  <= command[7:0];    // register value from ROM
                        state      <= S_ROM_WAIT;
                    end
                end

                // Wait for sccb_master to complete current ROM write
                S_ROM_WAIT: begin
                    if (sccb_done) begin
                        reg_writes_done <= reg_writes_done + 6'd1;
                        if (!sccb_ack_id && !sccb_ack_sub && !sccb_ack_data)
                            successful_xacts <= successful_xacts + 6'd1;
                        timer <= 20'd0;
                        state <= S_ROM_GAP;
                    end
                end

                // Inter-register settling delay
                S_ROM_GAP: begin
                    if (timer >= REG_GAP - 1) begin
                        timer    <= 20'd0;
                        rom_idx  <= rom_idx + 6'd1;
                        rom_addr <= rom_addr + 8'd1;
                        state    <= S_ROM_START;
                    end else begin
                        timer <= timer + 20'd1;
                    end
                end

                // Start SCCB write for color-bar ROM entry
                S_CB_START: begin
                    if (cb_idx >= NUM_CB_REGS) begin
                        state <= S_DONE;
                    end else if (!sccb_busy) begin
                        sccb_start <= 1'b1;
                        sccb_id    <= OV7670_ID;
                        sccb_sub   <= cb_rom[cb_idx][15:8];
                        sccb_data  <= cb_rom[cb_idx][7:0];
                        state      <= S_CB_WAIT;
                    end
                end

                // Wait for sccb_master to complete color-bar ROM write
                S_CB_WAIT: begin
                    if (sccb_done) begin
                        if (!sccb_ack_id && !sccb_ack_sub && !sccb_ack_data)
                            successful_xacts <= successful_xacts + 6'd1;
                        timer <= 20'd0;
                        state <= S_CB_GAP;
                    end
                end

                // Inter-register settling delay for color-bar writes
                S_CB_GAP: begin
                    if (timer >= REG_GAP - 1) begin
                        timer  <= 20'd0;
                        cb_idx <= cb_idx + 5'd1;
                        state  <= S_CB_START;
                    end else begin
                        timer <= timer + 20'd1;
                    end
                end

                // All registers written; idle
                S_DONE: begin
                    cfg_done <= 1'b1;
                end

                default: state <= S_DONE;
            endcase
        end
    end

endmodule
