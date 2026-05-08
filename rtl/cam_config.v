`timescale 1ns/1ps
// OV7670 power-up and register configuration sequencer.
// Drives cam_rst_n, then walks a 77-entry SCCB-write ROM to configure RGB565
// output, color matrix, gamma curve, AGC/AEC, and the "magic" registers
// (RSVD/CHLF/COM12/etc) the OV7670 needs for usable color.
//
// If test_pattern_en=1, two extra registers (SCALING_YSC + COM17) are written
// after the ROM to enable the chip's internal color-bar test pattern.
//
// Status outputs (for LED diagnostics):
//   cfg_done         - high once configuration finishes
//   reg_writes_done  - count of completed ROM writes (0..79)
//   successful_xacts - count of writes where the slave ACK'd all three bytes

module cam_config #(
    parameter integer RST_HOLD      = 625000,   // hold cam_rst_n low (25 ms @ 25 MHz)
    parameter integer POST_RST      = 250000,   // wait after release    (10 ms)
    parameter integer SOFT_RST_WAIT = 750000,   // wait after soft reset (30 ms; OV7670 datasheet min)
    parameter integer REG_GAP       = 2500,     // inter-register settling (~100 us)
    parameter [7:0]   OV7670_ID     = 8'h42     // SCCB write address
) (
    input  wire        clk,
    input  wire        rst,

    output reg         cam_rst_n,
    output reg         cam_pwdn,

    output wire        scl,
    inout  wire        sda,

    input  wire        test_pattern_en,

    output reg         cfg_done,
    output reg  [6:0]  reg_writes_done,
    output reg  [6:0]  successful_xacts
);

    // -----------------------------------------------------------------
    // SCCB master
    // -----------------------------------------------------------------
    reg        sccb_start;
    reg  [7:0] sccb_id, sccb_sub, sccb_data;
    wire       sccb_done, sccb_busy;
    wire       sccb_ack_id, sccb_ack_sub, sccb_ack_data;

    sccb_master u_sccb (
        .clk      (clk),
        .rst      (rst),
        .start    (sccb_start),
        .id       (sccb_id),
        .sub_addr (sccb_sub),
        .data     (sccb_data),
        .done     (sccb_done),
        .busy     (sccb_busy),
        .ack_id   (sccb_ack_id),
        .ack_sub  (sccb_ack_sub),
        .ack_data (sccb_ack_data),
        .scl      (scl),
        .sda      (sda)
    );

    // -----------------------------------------------------------------
    // Register ROM (77 entries) — proven OV7670 init sequence.
    // {sub_addr[15:8], value[7:0]}; sentinel 16'hFFFF marks end.
    // -----------------------------------------------------------------
    localparam integer NUM_REGS = 77;
    reg  [6:0]  rom_idx;
    reg  [15:0] command;

    always @(*) begin
        case (rom_idx)
            // Soft reset (twice — OV7670 quirk)
            7'h00: command = 16'h1280;
            7'h01: command = 16'h1280;
            // Output format: RGB565
            7'h02: command = 16'h1204;   // COM7   RGB output
            7'h03: command = 16'h1100;   // CLKRC  no prescale
            7'h04: command = 16'h40D0;   // COM15  RGB565 full range
            7'h05: command = 16'h0C00;   // COM3   no scaling
            7'h06: command = 16'h3E00;   // COM14
            7'h07: command = 16'h0400;   // COM1   disable CCIR656
            7'h08: command = 16'h3A04;   // TSLB
            7'h09: command = 16'h1418;   // COM9   AGC ceiling x4
            // Color matrix
            7'h0A: command = 16'h4FB3;
            7'h0B: command = 16'h50B3;
            7'h0C: command = 16'h5100;
            7'h0D: command = 16'h523D;
            7'h0E: command = 16'h53A7;
            7'h0F: command = 16'h54E4;
            7'h10: command = 16'h589E;
            7'h11: command = 16'h3D80;   // COM13 gamma enable
            // Window
            7'h12: command = 16'h1711;
            7'h13: command = 16'h1861;
            7'h14: command = 16'h32A4;
            7'h15: command = 16'h1903;
            7'h16: command = 16'h1A7B;
            7'h17: command = 16'h030A;
            7'h18: command = 16'h0F4B;
            7'h19: command = 16'h1E37;
            // "Magic" registers
            7'h1A: command = 16'h330B;
            7'h1B: command = 16'h3C78;
            7'h1C: command = 16'h6900;
            7'h1D: command = 16'h7400;
            7'h1E: command = 16'hB084;   // RSVD — required for good color
            7'h1F: command = 16'hB10C;
            7'h20: command = 16'hB20E;
            7'h21: command = 16'hB380;
            // Scaling
            7'h22: command = 16'h703A;
            7'h23: command = 16'h7135;
            7'h24: command = 16'h7211;
            7'h25: command = 16'h73F0;
            7'h26: command = 16'hA202;
            // Gamma curve
            7'h27: command = 16'h7A20;
            7'h28: command = 16'h7B10;
            7'h29: command = 16'h7C1E;
            7'h2A: command = 16'h7D35;
            7'h2B: command = 16'h7E5A;
            7'h2C: command = 16'h7F69;
            7'h2D: command = 16'h8076;
            7'h2E: command = 16'h8180;
            7'h2F: command = 16'h8288;
            7'h30: command = 16'h838F;
            7'h31: command = 16'h8496;
            7'h32: command = 16'h85A3;
            7'h33: command = 16'h86AF;
            7'h34: command = 16'h87C4;
            7'h35: command = 16'h88D7;
            7'h36: command = 16'h89E8;
            // AGC/AEC
            7'h37: command = 16'h13E0;
            7'h38: command = 16'h0000;
            7'h39: command = 16'h1000;
            7'h3A: command = 16'h0D40;
            7'h3B: command = 16'h1418;
            7'h3C: command = 16'hA505;
            7'h3D: command = 16'hAB07;
            7'h3E: command = 16'h2495;
            7'h3F: command = 16'h2533;
            7'h40: command = 16'h26E3;
            7'h41: command = 16'h9F78;
            7'h42: command = 16'hA068;
            7'h43: command = 16'hA103;
            7'h44: command = 16'hA6D8;
            7'h45: command = 16'hA7D8;
            7'h46: command = 16'hA8F0;
            7'h47: command = 16'hA990;
            7'h48: command = 16'hAA94;
            7'h49: command = 16'h13E7;   // COM8 — re-enable AGC + AEC + AWB
            // Misc
            7'h4A: command = 16'h6900;
            7'h4B: command = 16'h8C00;
            7'h4C: command = 16'h6B4A;
            default: command = 16'hFFFF;
        endcase
    end

    // Color-bar extra writes (SCALING_YSC bit7 + COM17 DSP color bar)
    localparam integer NUM_CB_REGS = 2;
    reg [15:0] cb_rom [0:NUM_CB_REGS-1];
    initial begin
        cb_rom[0] = 16'h7180;
        cb_rom[1] = 16'h4208;
    end

    // -----------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------
    localparam [3:0]
        S_RESET     = 4'd0,
        S_POST_RST  = 4'd1,
        S_SOFT_RST  = 4'd2,
        S_WAIT_DONE = 4'd3,
        S_SOFT_WAIT = 4'd4,
        S_ROM_GO    = 4'd5,
        S_ROM_WAIT  = 4'd6,
        S_ROM_GAP   = 4'd7,
        S_CB_GO     = 4'd8,
        S_CB_WAIT   = 4'd9,
        S_CB_GAP    = 4'd10,
        S_DONE      = 4'd11;

    reg [3:0]  state;
    reg [19:0] timer;
    reg [4:0]  cb_idx;

    initial begin
        state            = S_RESET;
        timer            = 20'd0;
        rom_idx          = 7'd0;
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

    always @(posedge clk) begin
        if (rst) begin
            state            <= S_RESET;
            timer            <= 20'd0;
            rom_idx          <= 7'd0;
            cb_idx           <= 5'd0;
            cam_rst_n        <= 1'b0;
            cam_pwdn         <= 1'b0;
            cfg_done         <= 1'b0;
            reg_writes_done  <= 7'd0;
            successful_xacts <= 7'd0;
            sccb_start       <= 1'b0;
        end else begin
            sccb_start <= 1'b0;

            case (state)
                S_RESET: begin
                    cam_rst_n <= 1'b0;
                    cam_pwdn  <= 1'b0;
                    if (timer >= RST_HOLD - 1) begin
                        cam_rst_n <= 1'b1;
                        timer     <= 20'd0;
                        state     <= S_POST_RST;
                    end else timer <= timer + 20'd1;
                end

                S_POST_RST: begin
                    if (timer >= POST_RST - 1) begin
                        timer <= 20'd0;
                        state <= S_SOFT_RST;
                    end else timer <= timer + 20'd1;
                end

                S_SOFT_RST: begin
                    if (!sccb_busy) begin
                        sccb_start <= 1'b1;
                        sccb_id    <= OV7670_ID;
                        sccb_sub   <= 8'h12;     // COM7
                        sccb_data  <= 8'h80;     // soft reset
                        state      <= S_WAIT_DONE;
                    end
                end

                S_WAIT_DONE: begin
                    if (sccb_done) begin
                        if (!sccb_ack_id && !sccb_ack_sub && !sccb_ack_data)
                            successful_xacts <= successful_xacts + 7'd1;
                        timer <= 20'd0;
                        state <= S_SOFT_WAIT;
                    end
                end

                S_SOFT_WAIT: begin
                    if (timer >= SOFT_RST_WAIT - 1) begin
                        timer   <= 20'd0;
                        rom_idx <= 7'd0;
                        state   <= S_ROM_GO;
                    end else timer <= timer + 20'd1;
                end

                S_ROM_GO: begin
                    if (rom_idx >= NUM_REGS) begin
                        cb_idx <= 5'd0;
                        state  <= test_pattern_en ? S_CB_GO : S_DONE;
                    end else if (!sccb_busy) begin
                        sccb_start <= 1'b1;
                        sccb_id    <= OV7670_ID;
                        sccb_sub   <= command[15:8];
                        sccb_data  <= command[7:0];
                        state      <= S_ROM_WAIT;
                    end
                end

                S_ROM_WAIT: begin
                    if (sccb_done) begin
                        reg_writes_done <= reg_writes_done + 7'd1;
                        if (!sccb_ack_id && !sccb_ack_sub && !sccb_ack_data)
                            successful_xacts <= successful_xacts + 7'd1;
                        timer <= 20'd0;
                        state <= S_ROM_GAP;
                    end
                end

                S_ROM_GAP: begin
                    if (timer >= REG_GAP - 1) begin
                        timer   <= 20'd0;
                        rom_idx <= rom_idx + 7'd1;
                        state   <= S_ROM_GO;
                    end else timer <= timer + 20'd1;
                end

                S_CB_GO: begin
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

                S_CB_WAIT: begin
                    if (sccb_done) begin
                        reg_writes_done <= reg_writes_done + 7'd1;
                        if (!sccb_ack_id && !sccb_ack_sub && !sccb_ack_data)
                            successful_xacts <= successful_xacts + 7'd1;
                        timer <= 20'd0;
                        state <= S_CB_GAP;
                    end
                end

                S_CB_GAP: begin
                    if (timer >= REG_GAP - 1) begin
                        timer  <= 20'd0;
                        cb_idx <= cb_idx + 5'd1;
                        state  <= S_CB_GO;
                    end else timer <= timer + 20'd1;
                end

                S_DONE: cfg_done <= 1'b1;

                default: state <= S_DONE;
            endcase
        end
    end

endmodule
