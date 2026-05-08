`timescale 1ns/1ps
// ycbcr_to_rgb444.v
// Converts YCbCr (Y3:Cb2:Cr2) back to RGB444 for VGA display.
// Includes 2×2 Bayer ordered dithering on the Y channel.
//
// Input encoding:
//   Y  [2:0] : luminance (0=black, 7=white)
//   Cb [1:0] : blue chrominance
//   Cr [1:0] : red  chrominance
//
// Chroma encoding (center = 1 = neutral):
//   0 = channel much less than average → strong negative offset
//   1 = channel near average           → ZERO offset (neutral)
//   2 = channel somewhat above average → moderate positive offset
//   3 = channel much above average     → strong positive offset

module ycbcr_to_rgb444 (
    input  wire [2:0]  in_y,       // Y (0..7)
    input  wire [1:0]  in_cb,      // Cb (0..3, center=1)
    input  wire [1:0]  in_cr,      // Cr (0..3, center=1)
    input  wire        h_pos,      // h_count[0] for dithering
    input  wire        v_pos,      // v_count[0] for dithering
    output wire [11:0] out_rgb444
);

    // -----------------------------------------------------------------------
    // Bayer dithering on Y channel
    // 2×2 matrix adds sub-pixel offset for smoother brightness gradients
    // -----------------------------------------------------------------------
    reg [1:0] dither_offset;
    always @(*) begin
        case ({v_pos, h_pos})
            2'b00: dither_offset = 2'd0;
            2'b01: dither_offset = 2'd2;
            2'b10: dither_offset = 2'd3;
            2'b11: dither_offset = 2'd1;
        endcase
    end

    // Scale Y from 3-bit (0..7) to 4-bit (0..15) with dither
    wire [4:0] y_dithered = {1'b0, in_y, 1'b0} + {3'b0, dither_offset};
    wire [3:0] y_scaled = (y_dithered > 5'd15) ? 4'd15 : y_dithered[3:0];

    // -----------------------------------------------------------------------
    // Chroma decode: map 2-bit code to RGB offsets
    //
    // Cb controls Blue channel (positive = more blue, negative = more yellow)
    // Cr controls Red channel  (positive = more red,  negative = more cyan)
    // Green is derived: more blue+red = less green, less blue+red = more green
    //
    // Using a direct lookup for each chroma combination to avoid any
    // signed arithmetic issues. All values are unsigned with a bias.
    //
    // For Blue channel offset (from Cb):
    //   Cb=0: B_offset = -4 (strong blue deficit)
    //   Cb=1: B_offset =  0 (neutral)
    //   Cb=2: B_offset = +3 (moderate blue)
    //   Cb=3: B_offset = +6 (strong blue)
    //
    // For Red channel offset (from Cr):
    //   Cr=0: R_offset = -4 (strong red deficit)
    //   Cr=1: R_offset =  0 (neutral)
    //   Cr=2: R_offset = +3 (moderate red)
    //   Cr=3: R_offset = +6 (strong red)
    //
    // Green offset = -(R_offset + B_offset) / 2, approximated
    // -----------------------------------------------------------------------

    // Compute R, G, B using unsigned arithmetic with intermediate 5-bit values
    // to handle overflow/underflow, then clamp to [0, 15]

    reg [3:0] r4, g4, b4;

    always @(*) begin
        // Start from Y for all channels
        // Apply Cr offset to Red
        case (in_cr)
            2'd0: begin // strong red deficit → reduce R, boost G
                r4 = (y_scaled > 4'd4) ? y_scaled - 4'd4 : 4'd0;
            end
            2'd1: begin // neutral
                r4 = y_scaled;
            end
            2'd2: begin // moderate red
                r4 = (y_scaled < 4'd12) ? y_scaled + 4'd3 : 4'd15;
            end
            2'd3: begin // strong red
                r4 = (y_scaled < 4'd10) ? y_scaled + 4'd6 : 4'd15;
            end
        endcase

        // Apply Cb offset to Blue
        case (in_cb)
            2'd0: begin // strong blue deficit → reduce B
                b4 = (y_scaled > 4'd4) ? y_scaled - 4'd4 : 4'd0;
            end
            2'd1: begin // neutral
                b4 = y_scaled;
            end
            2'd2: begin // moderate blue
                b4 = (y_scaled < 4'd12) ? y_scaled + 4'd3 : 4'd15;
            end
            2'd3: begin // strong blue
                b4 = (y_scaled < 4'd10) ? y_scaled + 4'd6 : 4'd15;
            end
        endcase

        // Green: inverse of red+blue chroma
        // When red or blue is boosted, green is suppressed and vice versa
        // G = Y - (R_offset + B_offset) / 2
        case ({in_cr, in_cb})
            // Both neutral: G = Y
            4'b01_01: g4 = y_scaled;
            // One side boosted, other neutral
            4'b01_00: g4 = (y_scaled < 4'd13) ? y_scaled + 4'd2 : 4'd15; // blue deficit → more green
            4'b01_10: g4 = (y_scaled > 4'd2)  ? y_scaled - 4'd2 : 4'd0;  // moderate blue → less green
            4'b01_11: g4 = (y_scaled > 4'd3)  ? y_scaled - 4'd3 : 4'd0;  // strong blue → less green
            4'b00_01: g4 = (y_scaled < 4'd13) ? y_scaled + 4'd2 : 4'd15; // red deficit → more green
            4'b10_01: g4 = (y_scaled > 4'd2)  ? y_scaled - 4'd2 : 4'd0;  // moderate red → less green
            4'b11_01: g4 = (y_scaled > 4'd3)  ? y_scaled - 4'd3 : 4'd0;  // strong red → less green
            // Both deficit: strong green (= cyan-ish)
            4'b00_00: g4 = (y_scaled < 4'd11) ? y_scaled + 4'd4 : 4'd15;
            // Both boosted: suppress green strongly (= purple/magenta)
            4'b10_10: g4 = (y_scaled > 4'd4)  ? y_scaled - 4'd4 : 4'd0;
            4'b10_11: g4 = (y_scaled > 4'd5)  ? y_scaled - 4'd5 : 4'd0;
            4'b11_10: g4 = (y_scaled > 4'd5)  ? y_scaled - 4'd5 : 4'd0;
            4'b11_11: g4 = (y_scaled > 4'd6)  ? y_scaled - 4'd6 : 4'd0;
            // Mixed: one deficit, one boost (cancel for green)
            4'b00_10: g4 = y_scaled;     // red deficit + blue boost → neutral green
            4'b00_11: g4 = (y_scaled > 4'd1) ? y_scaled - 4'd1 : 4'd0;
            4'b10_00: g4 = y_scaled;     // blue deficit + red boost → neutral green
            4'b11_00: g4 = (y_scaled > 4'd1) ? y_scaled - 4'd1 : 4'd0;
        endcase
    end

    assign out_rgb444 = {r4, g4, b4};

endmodule
