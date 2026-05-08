`timescale 1ns/1ps
// YCbCr (Y3, Cb2, Cr2) -> RGB444.
//
// Bin layout (matches cam_capture thresholds):
//   bin 0 : diff < -48   -> strong deficit  (e.g., very non-blue pixel for Cb)
//   bin 1 : diff -48..-1 -> mild deficit    (slightly below neutral)
//   bin 2 : diff  0..47  -> mild positive   (slightly above neutral)
//   bin 3 : diff >= 48   -> strong positive (e.g., strongly blue pixel for Cb)
//
// NEUTRAL rule: bins 1 and 2 straddle zero, so their offsets must be
// antisymmetric: bin1 = -N, bin2 = +N for some small N.
// This ensures a gray pixel (R=G=B) roundtrips back to R=G=B.
//
// With 2x2 Bayer dither on luma, y4 ranges 0..15.
// R4 = clamp(y4 + r_off(Cr))
// B4 = clamp(y4 + b_off(Cb))
// G4 = clamp(y4 + g_off_cr(Cr) + g_off_cb(Cb))

module ycbcr_to_rgb444 (
    input  wire [2:0]  in_y,
    input  wire [1:0]  in_cb,
    input  wire [1:0]  in_cr,
    input  wire        h_pos,    // h_count[0] for dither
    input  wire        v_pos,    // v_count[0] for dither
    output wire [11:0] out_rgb444
);

    // Bayer 2x2 dither: alternates 0/1 in checkerboard pattern
    wire dither = h_pos ^ v_pos;
    wire [3:0] y4 = {in_y, dither};

    // ----- Cr -> R offset -----
    // Bin 1 (mild deficit) and bin 2 (mild positive) are antisymmetric
    reg signed [2:0] r_off;
    always @(*) case (in_cr)
        2'd0:    r_off = -3'sd3;   // strong R deficit
        2'd1:    r_off = -3'sd1;   // mild R deficit
        2'd2:    r_off =  3'sd1;   // mild R positive
        default: r_off =  3'sd3;   // strong R positive
    endcase

    // ----- Cb -> B offset -----
    reg signed [2:0] b_off;
    always @(*) case (in_cb)
        2'd0:    b_off = -3'sd3;   // strong B deficit
        2'd1:    b_off = -3'sd1;   // mild B deficit
        2'd2:    b_off =  3'sd1;   // mild B positive
        default: b_off =  3'sd3;   // strong B positive
    endcase

    // ----- Cr -> G offset (approx -3/4 * r_off, antisymmetric) -----
    reg signed [2:0] g_off_cr;
    always @(*) case (in_cr)
        2'd0:    g_off_cr =  3'sd2;   // strong R deficit -> G boosted
        2'd1:    g_off_cr =  3'sd1;   // mild R deficit   -> G slightly boosted
        2'd2:    g_off_cr = -3'sd1;   // mild R positive  -> G slightly reduced
        default: g_off_cr = -3'sd2;   // strong R positive -> G reduced
    endcase

    // ----- Cb -> G offset (approx -1/3 * b_off, antisymmetric) -----
    reg signed [2:0] g_off_cb;
    always @(*) case (in_cb)
        2'd0:    g_off_cb =  3'sd1;   // strong B deficit -> G boosted
        2'd1:    g_off_cb =  3'sd0;   // mild B deficit   -> no G change
        2'd2:    g_off_cb =  3'sd0;   // mild B positive  -> no G change
        default: g_off_cb = -3'sd1;   // strong B positive -> G reduced
    endcase

    wire signed [4:0] g_off = g_off_cr + g_off_cb;   // range: -4..+4

    // ----- Sum and clamp -----
    wire signed [5:0] r_sum = $signed({2'b0, y4}) + r_off;
    wire signed [5:0] b_sum = $signed({2'b0, y4}) + b_off;
    wire signed [5:0] g_sum = $signed({2'b0, y4}) + g_off;

    function [3:0] clamp4;
        input signed [5:0] x;
        begin
            if (x < 6'sd0)       clamp4 = 4'd0;
            else if (x > 6'sd15) clamp4 = 4'd15;
            else                 clamp4 = x[3:0];
        end
    endfunction

    assign out_rgb444 = {clamp4(r_sum), clamp4(g_sum), clamp4(b_sum)};

endmodule
