`timescale 1ns/1ps
// filter_pipeline.v
// Mux between four processing modes based on SW[1:0] (sw_mode) setting.
//
// Modes (sw_mode):
//   2'b00 — RAW:        YCbCr → RGB444 (with dithering)
//   2'b01 — INVERT:     YCbCr → RGB444 → bitwise NOT
//   2'b10 — COLOR_ISO:  YCbCr → RGB444 → channel isolation (sw32 selects R/G/B)
//   2'b11 — EDGE:       luma → line_buffer3 → 3×3 Sobel (threshold = sw74)
//
// Clocked on clk (= clk_25 in top).
// pix_valid is high during active video pixels (h_count < 640, v_count < 480).
// h_edge / v_edge are flags for Sobel border zeroing.
//
// Latency:
//   Modes 00/01/10: 0 combinational cycles → register once → 1 cycle latency
//   Mode  11: line_buffer3 has 1 registered read, filter_edge is comb
//             → effective 1 cycle latency (same as other modes)
//
// Parameters:
//   WIDTH — line width (default 640, override for test)

module filter_pipeline #(
    parameter WIDTH = 640
) (
    input  wire        clk,
    input  wire        rst,

    // Frame buffer pixel data (YCbCr format)
    input  wire [2:0]  fb_luma,       // Y (3 bits) from luma BRAM
    input  wire [3:0]  fb_chroma,     // {Cb[1:0], Cr[1:0]} from chroma BRAM

    // Current pixel position
    input  wire [9:0]  h_count,
    input  wire [9:0]  v_count,
    input  wire        pix_valid,    // high during active video

    // Filter select switches
    input  wire [1:0]  sw_mode,      // SW[1:0]: selects filter
    input  wire [1:0]  sw32,         // SW[3:2] sub-field for color isolation channel
    input  wire [3:0]  sw74,         // SW[7:4]: Sobel threshold

    // Edge flags (from vga_timing or external logic)
    input  wire        h_edge,       // h_count==0 or h_count==WIDTH-1
    input  wire        v_edge,       // v_count<2 or v_count>=479

    // Processed pixel output (RGB444)
    output reg  [11:0] rgb444_out
);

    // -----------------------------------------------------------------------
    // Stage 0: Convert YCbCr → RGB444 using ycbcr_to_rgb444 (combinational)
    // Includes 2×2 Bayer dithering on Y channel.
    // -----------------------------------------------------------------------
    wire [11:0] raw444;

    ycbcr_to_rgb444 u_ycbcr (
        .in_y      (fb_luma),
        .in_cb     (fb_chroma[3:2]),
        .in_cr     (fb_chroma[1:0]),
        .h_pos     (h_count[0]),
        .v_pos     (v_count[0]),
        .out_rgb444(raw444)
    );

    // -----------------------------------------------------------------------
    // Stage 0: filter_invert (combinational)
    // -----------------------------------------------------------------------
    wire [11:0] inv444 = ~raw444;

    // -----------------------------------------------------------------------
    // Stage 0: filter_color_iso (combinational)
    // sw32: 00=R only, 01=G only, 10=B only, 11=pass-through (R)
    // -----------------------------------------------------------------------
    wire [11:0] iso444;
    assign iso444 = (sw32 == 2'b00) ? {raw444[11:8], 4'h0, 4'h0}  // R only
                  : (sw32 == 2'b01) ? {4'h0, raw444[7:4], 4'h0}  // G only
                  : (sw32 == 2'b10) ? {4'h0, 4'h0, raw444[3:0]}  // B only
                  :                   {raw444[11:8], 4'h0, 4'h0};  // default R

    // -----------------------------------------------------------------------
    // Stage 0 → line_buffer3 for EDGE mode
    // line_buffer3 takes Y (luma) directly — 3-bit pix_in
    // -----------------------------------------------------------------------
    wire [2:0]  top_l, top_c, top_r;
    wire [2:0]  mid_l, mid_c, mid_r;
    wire [2:0]  bot_l, bot_c, bot_r;

    line_buffer3 #(.WIDTH(WIDTH)) u_lb3 (
        .clk       (clk),
        .rst       (rst),
        .pix_in    (fb_luma),
        .pix_valid (pix_valid),
        .h_count   (h_count),
        .v_count   (v_count),
        .top_l     (top_l), .top_c (top_c), .top_r (top_r),
        .mid_l     (mid_l), .mid_c (mid_c), .mid_r (mid_r),
        .bot_l     (bot_l), .bot_c (bot_c), .bot_r (bot_r)
    );

    // -----------------------------------------------------------------------
    // Stage 1: filter_edge (combinational, reads line_buffer3 registered output)
    // -----------------------------------------------------------------------
    wire [11:0] edge444;

    filter_edge u_fedge (
        .top_l     (top_l), .top_c (top_c), .top_r (top_r),
        .mid_l     (mid_l), .mid_c (mid_c), .mid_r (mid_r),
        .bot_l     (bot_l), .bot_c (bot_c), .bot_r (bot_r),
        .threshold (sw74),
        .h_edge    (h_edge),
        .v_edge    (v_edge),
        .out_rgb444(edge444)
    );

    // -----------------------------------------------------------------------
    // Output register: select mode and latch result
    // Non-edge modes have 0 extra latency (pure comb); registered here.
    // Edge mode already has 1-cycle latency from line_buffer3, also registered here.
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            rgb444_out <= 12'h000;
        end else begin
            case (sw_mode)
                2'b00:   rgb444_out <= raw444;
                2'b01:   rgb444_out <= inv444;
                2'b10:   rgb444_out <= iso444;
                default: rgb444_out <= edge444;
            endcase
        end
    end

endmodule
