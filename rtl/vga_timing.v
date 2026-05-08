`timescale 1ns/1ps
// VGA 640x480 @ 60 Hz timing generator (25 MHz pixel clock).
//
// H: active=640, FP=16, sync=96, BP=48 -> total 800
// V: active=480, FP=10, sync=2,  BP=29 -> total 521
// HSYNC and VSYNC are active-LOW.
//
// rd_addr is combinational (base_of_row + h_count) using a running line base
// accumulator (no per-pixel multiplication). The frame buffer adds 1 cycle
// of BRAM read latency, so the caller should delay active_video to match the
// downstream pipeline when gating VGA output.

module vga_timing (
    input  wire        clk,
    input  wire        rst,
    output reg  [9:0]  h_count,
    output reg  [9:0]  v_count,
    output wire        hsync,
    output wire        vsync,
    output wire        active_video,
    output wire [18:0] rd_addr
);

    localparam H_ACTIVE = 10'd640;
    localparam H_FP     = 10'd16;
    localparam H_SYNC   = 10'd96;
    localparam H_BP     = 10'd48;
    localparam H_TOTAL  = H_ACTIVE + H_FP + H_SYNC + H_BP;   // 800

    localparam V_ACTIVE = 10'd480;
    localparam V_FP     = 10'd10;
    localparam V_SYNC   = 10'd2;
    localparam V_BP     = 10'd29;
    localparam V_TOTAL  = V_ACTIVE + V_FP + V_SYNC + V_BP;   // 521

    localparam H_SYNC_START = H_ACTIVE + H_FP;             // 656
    localparam H_SYNC_END   = H_ACTIVE + H_FP + H_SYNC;    // 752
    localparam V_SYNC_START = V_ACTIVE + V_FP;             // 490
    localparam V_SYNC_END   = V_ACTIVE + V_FP + V_SYNC;    // 492

    initial begin
        h_count = 10'd0;
        v_count = 10'd0;
    end

    // -----------------------------------------------------------------
    // Pixel counters
    // -----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else if (h_count == H_TOTAL - 10'd1) begin
            h_count <= 10'd0;
            v_count <= (v_count == V_TOTAL - 10'd1) ? 10'd0 : v_count + 10'd1;
        end else begin
            h_count <= h_count + 10'd1;
        end
    end

    assign hsync = ~((h_count >= H_SYNC_START) && (h_count < H_SYNC_END));
    assign vsync = ~((v_count >= V_SYNC_START) && (v_count < V_SYNC_END));
    assign active_video = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);

    // -----------------------------------------------------------------
    // Running line base: tracks v_count * 640 incrementally
    //   - Wraps to 0 at end of frame
    //   - Holds during V blanking (v_count >= V_ACTIVE-1 stops adding)
    // -----------------------------------------------------------------
    reg [18:0] line_base;

    initial line_base = 19'd0;

    always @(posedge clk) begin
        if (rst) begin
            line_base <= 19'd0;
        end else if (h_count == H_TOTAL - 10'd1) begin
            if (v_count == V_TOTAL - 10'd1)
                line_base <= 19'd0;
            else if (v_count < V_ACTIVE - 10'd1)
                line_base <= line_base + 19'd640;
        end
    end

    wire in_active = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
    assign rd_addr = in_active ? (line_base + {9'd0, h_count}) : 19'd0;

endmodule
