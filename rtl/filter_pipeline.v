`timescale 1ns/1ps
// Filter selector / output pipeline.
//
// Mode (sw_mode):
//   2'b00  RAW       — YCbCr decoded to RGB444 (with dither)
//   2'b01  INVERT    — bitwise NOT of raw
//   2'b10  COLOR_ISO — pass selected channel only (sw32: 00=R, 01=G, 10=B, 11=R)
//   2'b11  EDGE      — 3x3 Sobel on luma (threshold = sw74)
//
// Pipeline depth (frame buffer output -> rgb444_out):
//   raw / invert / iso : 0 (ycbcr comb)   + 1 cycle (output reg) = 1 cycle
//   edge               : 1 (line_buffer3) + 1 cycle (output reg) = 2 cycles
// Edge mode lags non-edge by 1 pixel; filter_edge already blanks the leftmost
// columns via h_edge so the shift is invisible. Matches the 320 path style.
//
// h_count / v_count are passed through for dither (raw) and edge gating (edge).

module filter_pipeline #(
    parameter integer WIDTH = 640
) (
    input  wire        clk,
    input  wire        rst,

    input  wire [2:0]  fb_luma,
    input  wire [3:0]  fb_chroma,

    input  wire [9:0]  h_count,
    input  wire [9:0]  v_count,
    input  wire        pix_valid,

    input  wire [1:0]  sw_mode,
    input  wire [1:0]  sw32,
    input  wire [3:0]  sw74,

    input  wire        h_edge,
    input  wire        v_edge,

    output reg  [11:0] rgb444_out
);

    // -----------------------------------------------------------------
    // RAW: YCbCr -> RGB444 (combinational)
    // -----------------------------------------------------------------
    wire [11:0] raw444;

    ycbcr_to_rgb444 u_ycbcr (
        .in_y       (fb_luma),
        .in_cb      (fb_chroma[3:2]),
        .in_cr      (fb_chroma[1:0]),
        .h_pos      (h_count[0]),
        .v_pos      (v_count[0]),
        .out_rgb444 (raw444)
    );

    // INVERT and COLOR_ISO derived from raw444
    wire [11:0] inv444 = ~raw444;
    wire [11:0] iso444 = (sw32 == 2'b00) ? {raw444[11:8],  4'h0,         4'h0       } :
                         (sw32 == 2'b01) ? {4'h0,          raw444[7:4],  4'h0       } :
                         (sw32 == 2'b10) ? {4'h0,          4'h0,         raw444[3:0]} :
                                           {raw444[11:8],  4'h0,         4'h0       };

    // -----------------------------------------------------------------
    // EDGE: 3x3 Sobel on luma (line_buffer3 has 1-cycle registered read,
    // filter_edge is combinational).
    // -----------------------------------------------------------------
    wire [2:0] tl, tc, tr, ml, mc, mr, bl, bc, br;

    line_buffer3 #(.WIDTH(WIDTH)) u_lb3 (
        .clk       (clk),
        .rst       (rst),
        .pix_in    (fb_luma),
        .pix_valid (pix_valid),
        .h_count   (h_count),
        .v_count   (v_count),
        .top_l     (tl), .top_c (tc), .top_r (tr),
        .mid_l     (ml), .mid_c (mc), .mid_r (mr),
        .bot_l     (bl), .bot_c (bc), .bot_r (br)
    );

    wire [11:0] edge444;

    filter_edge u_edge (
        .top_l     (tl), .top_c (tc), .top_r (tr),
        .mid_l     (ml), .mid_c (mc), .mid_r (mr),
        .bot_l     (bl), .bot_c (bc), .bot_r (br),
        .threshold (sw74),
        .h_edge    (h_edge),
        .v_edge    (v_edge),
        .out_rgb444(edge444)
    );

    // -----------------------------------------------------------------
    // Mode select + output register (single pipeline stage)
    // -----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            rgb444_out <= 12'h000;
        end else case (sw_mode)
            2'b00:   rgb444_out <= raw444;
            2'b01:   rgb444_out <= inv444;
            2'b10:   rgb444_out <= iso444;
            default: rgb444_out <= edge444;
        endcase
    end

endmodule
