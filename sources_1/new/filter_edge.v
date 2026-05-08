`timescale 1ns/1ps
// filter_edge.v
// 3×3 Sobel edge detection on Y (luma) channel.
// Outputs white (0xFFF) for edges, black (0x000) otherwise.

module filter_edge (
    input  wire [2:0]  top_l, top_c, top_r,
    input  wire [2:0]  mid_l, mid_c, mid_r,
    input  wire [2:0]  bot_l, bot_c, bot_r,
    input  wire [3:0]  threshold,
    input  wire        h_edge,
    input  wire        v_edge,
    output wire [11:0] out_rgb444
);

    wire [2:0] y00 = top_l;
    wire [2:0] y01 = top_c;
    wire [2:0] y02 = top_r;
    wire [2:0] y10 = mid_l;
    wire [2:0] y12 = mid_r;
    wire [2:0] y20 = bot_l;
    wire [2:0] y21 = bot_c;
    wire [2:0] y22 = bot_r;

    wire signed [5:0] right_col = $signed({3'b0, y02}) + $signed({2'b0, y12, 1'b0}) + $signed({3'b0, y22});
    wire signed [5:0] left_col  = $signed({3'b0, y00}) + $signed({2'b0, y10, 1'b0}) + $signed({3'b0, y20});
    wire signed [5:0] bot_row   = $signed({3'b0, y20}) + $signed({2'b0, y21, 1'b0}) + $signed({3'b0, y22});
    wire signed [5:0] top_row   = $signed({3'b0, y00}) + $signed({2'b0, y01, 1'b0}) + $signed({3'b0, y02});

    wire signed [5:0] Gx = right_col - left_col;
    wire signed [5:0] Gy = bot_row   - top_row;

    wire [5:0] abs_Gx = Gx[5] ? (~Gx + 6'd1) : Gx;
    wire [5:0] abs_Gy = Gy[5] ? (~Gy + 6'd1) : Gy;

    wire [6:0] mag = {1'b0, abs_Gx} + {1'b0, abs_Gy};
    wire [6:0] thresh_scaled = {3'b000, threshold};

    assign out_rgb444 = (h_edge || v_edge) ? 12'h000
                      : (mag > thresh_scaled)  ? 12'hFFF
                      :                          12'h000;

endmodule
