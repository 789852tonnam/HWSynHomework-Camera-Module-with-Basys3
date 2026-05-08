`timescale 1ns/1ps
// filter_edge.v
// 3×3 Sobel edge detection on Y (luma) channel.
//
// Input: 3-bit Y values from line_buffer3 (range 0..7)
//
// Sobel kernels:
//   Gx = (p02+2*p12+p22) - (p00+2*p10+p20)   (right - left column sum)
//   Gy = (p20+2*p21+p22) - (p00+2*p01+p02)   (bottom - top row sum)
//   mag = |Gx| + |Gy|  (approximation to gradient magnitude)
//
// Output:
//   out_rgb444 = 12'hFFF (white) if mag > threshold, else 12'h000 (black)
//
// Pixel numbering (row, col):
//   (00, 01, 02)     p00=top_l,  p01=top_c,  p02=top_r
//   (10, 11, 12)     p10=mid_l,  p11=mid_c,  p12=mid_r
//   (20, 21, 22)     p20=bot_l,  p21=bot_c,  p22=bot_r
//
// threshold: SW[7:4] (4-bit)
// Edge pixels (h_count=0/639 or v_count=0/1) are forced to black.

module filter_edge (
    // 3×3 neighbourhood (Y luma, 3 bits each)
    input  wire [2:0]  top_l, top_c, top_r,
    input  wire [2:0]  mid_l, mid_c, mid_r,
    input  wire [2:0]  bot_l, bot_c, bot_r,

    // Threshold (SW[7:4])
    input  wire [3:0]  threshold,

    // Position flags for edge zeroing
    input  wire        h_edge,    // 1 when h_count==0 or h_count==639
    input  wire        v_edge,    // 1 when v_count<2 or v_count>=479

    // Output
    output wire [11:0] out_rgb444
);

    // -----------------------------------------------------------------------
    // Y values are already luma — use directly (no need to compute from RGB)
    // Range: 0..7, fits in 3 bits
    // -----------------------------------------------------------------------
    wire [2:0] y00 = top_l;
    wire [2:0] y01 = top_c;
    wire [2:0] y02 = top_r;
    wire [2:0] y10 = mid_l;
    wire [2:0] y12 = mid_r;  // y11 (centre) not used in Sobel
    wire [2:0] y20 = bot_l;
    wire [2:0] y21 = bot_c;
    wire [2:0] y22 = bot_r;

    // -----------------------------------------------------------------------
    // Sobel: Gx and Gy
    // Max value of each column/row sum: (7+14+7) = 28 → 5 bits
    // Gx/Gy max = 28 → needs 6 bits signed
    // -----------------------------------------------------------------------
    wire signed [5:0] right_col = $signed({3'b0, y02}) + $signed({2'b0, y12, 1'b0}) + $signed({3'b0, y22});
    wire signed [5:0] left_col  = $signed({3'b0, y00}) + $signed({2'b0, y10, 1'b0}) + $signed({3'b0, y20});
    wire signed [5:0] bot_row   = $signed({3'b0, y20}) + $signed({2'b0, y21, 1'b0}) + $signed({3'b0, y22});
    wire signed [5:0] top_row   = $signed({3'b0, y00}) + $signed({2'b0, y01, 1'b0}) + $signed({3'b0, y02});

    wire signed [5:0] Gx = right_col - left_col;
    wire signed [5:0] Gy = bot_row   - top_row;

    // Absolute values
    wire [5:0] abs_Gx = Gx[5] ? (~Gx + 6'd1) : Gx;
    wire [5:0] abs_Gy = Gy[5] ? (~Gy + 6'd1) : Gy;

    // Magnitude (max 56, fits in 6 bits)
    wire [6:0] mag = {1'b0, abs_Gx} + {1'b0, abs_Gy};

    // -----------------------------------------------------------------------
    // Threshold comparison
    // -----------------------------------------------------------------------
    wire [6:0] thresh_scaled = {3'b000, threshold};

    // Output: white if mag > thresh_scaled AND not on an edge pixel
    assign out_rgb444 = (h_edge || v_edge) ? 12'h000
                      : (mag > thresh_scaled)  ? 12'hFFF
                      :                          12'h000;

endmodule
