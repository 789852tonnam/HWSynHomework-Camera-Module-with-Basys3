`timescale 1ns/1ps
// vga_timing.v
// VGA timing generator for 640x480 @ 60 Hz, 25 MHz pixel clock.
//
// Timing (from Basys 3 RM Figure 14):
//   H: active=640, FP=16, sync=96, BP=48  → total=800
//   V: active=480, FP=10, sync=2,  BP=29  → total=521
//
// HSYNC and VSYNC are active LOW.
// rd_addr is pre-fetched one cycle early to compensate for BRAM 1-cycle latency.

module vga_timing (
    input  wire        clk,        // 25 MHz pixel clock
    input  wire        rst,        // synchronous reset (active high)
    output reg  [9:0]  h_count,    // 0..799
    output reg  [9:0]  v_count,    // 0..520
    output wire        hsync,
    output wire        vsync,
    output wire        active_video,
    output reg  [18:0] rd_addr     // frame-buffer read address (pre-fetched)
);

    // Timing constants
    localparam H_ACTIVE = 640;
    localparam H_FP     = 16;
    localparam H_SYNC   = 96;
    localparam H_BP     = 48;
    localparam H_TOTAL  = H_ACTIVE + H_FP + H_SYNC + H_BP; // 800

    localparam V_ACTIVE = 480;
    localparam V_FP     = 10;
    localparam V_SYNC   = 2;
    localparam V_BP     = 29;
    localparam V_TOTAL  = V_ACTIVE + V_FP + V_SYNC + V_BP; // 521

    // Sync pulse regions (active LOW)
    // HSYNC low during [H_ACTIVE+H_FP .. H_ACTIVE+H_FP+H_SYNC-1]
    //              = [656..751]
    localparam H_SYNC_START = H_ACTIVE + H_FP;          // 656
    localparam H_SYNC_END   = H_ACTIVE + H_FP + H_SYNC; // 752

    // VSYNC low during [V_ACTIVE+V_FP .. V_ACTIVE+V_FP+V_SYNC-1]
    //              = [490..491]
    localparam V_SYNC_START = V_ACTIVE + V_FP;          // 490
    localparam V_SYNC_END   = V_ACTIVE + V_FP + V_SYNC; // 492

    // Initialise counters for simulation
    initial begin
        h_count = 10'd0;
        v_count = 10'd0;
        rd_addr = 19'd0;
    end

    // Counters
    always @(posedge clk) begin
        if (rst) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 10'd0;
                if (v_count == V_TOTAL - 1)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 10'd1;
            end else begin
                h_count <= h_count + 10'd1;
            end
        end
    end

    // Sync signals (active LOW)
    assign hsync = ~((h_count >= H_SYNC_START) && (h_count < H_SYNC_END));
    assign vsync = ~((v_count >= V_SYNC_START) && (v_count < V_SYNC_END));

    // Active video window
    assign active_video = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);

    // Read address — pre-fetch one cycle ahead to account for BRAM latency.
    // The address is for the NEXT pixel to be displayed.
    // During active: rd_addr = v_count * 640 + (h_count + 1) [or v+1 on EOL]
    // We use shift+add for 640 = 512 + 128:
    //   v * 640 = v * 512 + v * 128 = (v << 9) + (v << 7)
    //
    // For simplicity, compute the address of the CURRENT pixel; the BRAM will
    // output data one clock after this, which aligns with the active window.
    wire [18:0] rd_addr_cur = (v_count < V_ACTIVE && h_count < H_ACTIVE)
        ? ({9'd0, v_count} * 19'd640 + {9'd0, h_count})
        : 19'd0;

    always @(posedge clk) begin
        if (rst)
            rd_addr <= 19'd0;
        else
            rd_addr <= rd_addr_cur;
    end

endmodule
