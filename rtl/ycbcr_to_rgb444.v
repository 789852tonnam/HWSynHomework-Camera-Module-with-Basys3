`timescale 1ns/1ps
// YCbCr (Y3, Cb2, Cr2) -> RGB444 with 2x2 Bayer dither on luma.
//
// Math (BT.601, simplified to small signed offsets in 4-bit RGB space):
//   y4   = (Y3 << 1) | dither2x2     (0..15, dithered)
//   r4   = clamp(y4 + offsetR(Cr))   offsetR(Cr) = {-3,  0, +2, +3}
//   b4   = clamp(y4 + offsetB(Cb))   offsetB(Cb) = {-3,  0, +2, +3}
//   g4   = clamp(y4 + offsetG_Cr(Cr) + offsetG_Cb(Cb))
//          offsetG_Cr  ~ -(3/4)*offsetR -> {+2,  0, -2, -2}
//          offsetG_Cb  ~ -(1/3)*offsetB -> {+1,  0, -1, -1}
//
// Bin 1 is the "neutral" bin (covers diff in [-16, +16) per cam_capture). Its
// offset MUST be 0 so that R=G=B inputs decode back to R=G=B output — otherwise
// the whole frame picks up a chroma tint. Bins 2 and 3 keep monotonicity.
//
// Replaces the 16-case green lookup in the previous design with two small
// signed LUTs and a single signed add. Output channels are clamped to 0..15.

module ycbcr_to_rgb444 (
    input  wire [2:0]  in_y,
    input  wire [1:0]  in_cb,
    input  wire [1:0]  in_cr,
    input  wire        h_pos,           // h_count[0]
    input  wire        v_pos,           // v_count[0]
    output wire [11:0] out_rgb444
);

    // Bayer 2x2 dither: {0, 1, 1, 0} for (v_pos, h_pos)
    wire dither = h_pos ^ v_pos;
    wire [3:0] y4 = {in_y, dither};

    // ----- Cr -> R offset -----
    reg signed [2:0] r_off;
    always @(*) case (in_cr)
        2'd0:    r_off = -3'sd3;
        2'd1:    r_off =  3'sd0;
        2'd2:    r_off =  3'sd2;
        default: r_off =  3'sd3;
    endcase

    // ----- Cb -> B offset -----
    reg signed [2:0] b_off;
    always @(*) case (in_cb)
        2'd0:    b_off = -3'sd3;
        2'd1:    b_off =  3'sd0;
        2'd2:    b_off =  3'sd2;
        default: b_off =  3'sd3;
    endcase

    // ----- Cr -> G offset (~ -3/4 * r_off) -----
    reg signed [2:0] g_off_cr;
    always @(*) case (in_cr)
        2'd0:    g_off_cr =  3'sd2;
        2'd1:    g_off_cr =  3'sd0;
        2'd2:    g_off_cr = -3'sd2;
        default: g_off_cr = -3'sd2;
    endcase

    // ----- Cb -> G offset (~ -1/3 * b_off) -----
    reg signed [2:0] g_off_cb;
    always @(*) case (in_cb)
        2'd0:    g_off_cb =  3'sd1;
        2'd1:    g_off_cb =  3'sd0;
        2'd2:    g_off_cb = -3'sd1;
        default: g_off_cb = -3'sd1;
    endcase

    wire signed [4:0] g_off = g_off_cr + g_off_cb;       // -4 .. +4

    // ----- Sum and clamp to 4 bits -----
    wire signed [5:0] r_sum = $signed({2'b0, y4}) + r_off;
    wire signed [5:0] b_sum = $signed({2'b0, y4}) + b_off;
    wire signed [5:0] g_sum = $signed({2'b0, y4}) + g_off;

    function [3:0] clamp4;
        input signed [5:0] x;
        begin
            if (x < 6'sd0)        clamp4 = 4'd0;
            else if (x > 6'sd15)  clamp4 = 4'd15;
            else                  clamp4 = x[3:0];
        end
    endfunction

    assign out_rgb444 = {clamp4(r_sum), clamp4(g_sum), clamp4(b_sum)};

endmodule
