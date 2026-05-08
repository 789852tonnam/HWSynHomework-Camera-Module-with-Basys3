`timescale 1ns/1ps
// 3x3 Sobel edge detector on Y (luma).
//
//   Gx = (p02 + 2 p12 + p22) - (p00 + 2 p10 + p20)   (right - left column sum)
//   Gy = (p20 + 2 p21 + p22) - (p00 + 2 p01 + p02)   (bottom - top  row sum)
//   mag = |Gx| + |Gy|        (L1 approximation)
//
// Y is 3-bit (0..7). Each weighted column/row sum max = 7 + 14 + 7 = 28 -> 5 bits.
// Gx, Gy fit in signed 6 bits; |Gx|+|Gy| fits in unsigned 7 bits.
//
// Output: white (12'hFFF) if mag > threshold AND not on a frame edge,
//         black (12'h000) otherwise. threshold is the SW[7:4] 4-bit value
//         zero-extended to the 7-bit comparator width.

module filter_edge (
    input  wire [2:0]  top_l, top_c, top_r,
    input  wire [2:0]  mid_l, mid_c, mid_r,
    input  wire [2:0]  bot_l, bot_c, bot_r,

    input  wire [3:0]  threshold,
    input  wire        h_edge,
    input  wire        v_edge,

    output wire [11:0] out_rgb444
);

    wire signed [5:0] right_col = $signed({3'b0, top_r}) + $signed({2'b0, mid_r, 1'b0}) + $signed({3'b0, bot_r});
    wire signed [5:0] left_col  = $signed({3'b0, top_l}) + $signed({2'b0, mid_l, 1'b0}) + $signed({3'b0, bot_l});
    wire signed [5:0] bot_row   = $signed({3'b0, bot_l}) + $signed({2'b0, bot_c, 1'b0}) + $signed({3'b0, bot_r});
    wire signed [5:0] top_row   = $signed({3'b0, top_l}) + $signed({2'b0, top_c, 1'b0}) + $signed({3'b0, top_r});

    wire signed [5:0] gx = right_col - left_col;
    wire signed [5:0] gy = bot_row   - top_row;

    wire [5:0] abs_gx = gx[5] ? -gx : gx;
    wire [5:0] abs_gy = gy[5] ? -gy : gy;
    wire [6:0] mag    = {1'b0, abs_gx} + {1'b0, abs_gy};

    wire edge_on = (mag > {3'b0, threshold});
    assign out_rgb444 = (h_edge || v_edge) ? 12'h000 :
                        edge_on            ? 12'hFFF : 12'h000;

endmodule
