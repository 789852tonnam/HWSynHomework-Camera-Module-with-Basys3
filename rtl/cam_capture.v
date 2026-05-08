`timescale 1ns/1ps
// cam_capture.v
// Captures OV7670 camera data and converts RGB565 to YCbCr 4:2:2.
//
// Ported from ov7670_capture.v in the uec2_projekt reference design.
//
// Key design change: Camera signals (d, href, vsync) are sampled on the
// FALLING edge of PCLK. The OV7670 datasheet (Figure 5) shows data
// stable in the middle of the PCLK high period.
//
// Pixel format: OV7670 sends 2 bytes per pixel in RGB565:
//   Byte 0 (first PCLK with href=1): bits [15:8] of RGB565
//   Byte 1 (second PCLK with href=1): bits [7:0]  of RGB565
//
// YCbCr conversion (shift-add approximation):
//   Y  = (R5 + G5 + B5) / 4,   truncated to 3 bits (0..7)
//   Cb = (B5 - Y_full) / 8 + 2, clamped to 2 bits (0..3)
//   Cr = (R5 - Y_full) / 8 + 2, clamped to 2 bits (0..3)
//
// Chroma is written once per pixel pair (even-column pixels).
//
// Parameters:
//   IMG_WIDTH  — pixels per line (default 640)
//   IMG_HEIGHT — lines per frame (default 480)

module cam_capture #(
    parameter IMG_WIDTH  = 640,
    parameter IMG_HEIGHT = 480
) (
    input  wire        pclk_in,

    input  wire [7:0]  d_in,
    input  wire        href,
    input  wire        vsync,

    output reg  [18:0] wr_addr,
    output reg  [2:0]  wr_luma,       // Y (3 bits)
    output reg  [3:0]  wr_chroma,     // {Cb[1:0], Cr[1:0]}
    output reg         wr_en,
    output reg         wr_chroma_en,  // high on even columns
    output reg         vsync_pulse
);

    // -----------------------------------------------------------------------
    // Negedge latches (camera signals sampled at stable point)
    // -----------------------------------------------------------------------
    reg [7:0]  latched_d;
    reg        latched_href;
    reg        latched_vsync;

    // -----------------------------------------------------------------------
    // Posedge state
    // -----------------------------------------------------------------------
    reg [15:0] d_latch;
    reg [6:0]  href_last;
    reg        href_hold;
    reg [18:0] address;
    reg        we_reg;

    // Track even/odd pixel columns for chroma write gating
    reg        col_phase;   // 0 = even column, 1 = odd column

    // -----------------------------------------------------------------------
    // Initial blocks — X-prop avoidance (critical for simulation correctness)
    // -----------------------------------------------------------------------
    initial begin
        latched_d     = 8'd0;
        latched_href  = 1'b0;
        latched_vsync = 1'b0;
        d_latch       = 16'd0;
        href_last     = 7'd0;
        href_hold     = 1'b0;
        address       = 19'd0;
        we_reg        = 1'b0;
        wr_addr       = 19'd0;
        wr_luma       = 3'd0;
        wr_chroma     = 4'd0;
        wr_en         = 1'b0;
        wr_chroma_en  = 1'b0;
        vsync_pulse   = 1'b0;
        col_phase     = 1'b0;
    end

    // -----------------------------------------------------------------------
    // Negedge: latch camera inputs
    // -----------------------------------------------------------------------
    always @(negedge pclk_in) begin
        latched_d     <= d_in;
        latched_href  <= href;
        latched_vsync <= vsync;
    end

    // -----------------------------------------------------------------------
    // Posedge: pixel accumulation and write-enable generation
    // Matches the reference's we_reg/href_last/d_latch/address logic exactly.
    // -----------------------------------------------------------------------
    always @(posedge pclk_in) begin
        vsync_pulse <= 1'b0;
        we_reg      <= 1'b0;   // default: clear

        // Address advance: when we_reg was high last cycle
        if (we_reg) begin
            address   <= address + 19'd1;
            col_phase <= ~col_phase;    // toggle even/odd
        end

        // Byte accumulation
        if (latched_href == 1'b1)
            d_latch <= {d_latch[7:0], latched_d};

        href_hold <= latched_href;

        if (latched_vsync == 1'b1) begin
            address     <= 19'd0;
            href_last   <= 7'd0;
            vsync_pulse <= 1'b1;
            col_phase   <= 1'b0;        // reset to even on new frame
        end else begin
            if (href_last[0] == 1'b1) begin
                we_reg    <= 1'b1;   // signal: complete pixel ready
                href_last <= 7'd0;
            end else begin
                href_last <= {href_last[5:0], latched_href};
            end
        end
    end

    // -----------------------------------------------------------------------
    // RGB565 channel extraction from d_latch
    //   r5 = bits [15:11] (5-bit red,   0..31)
    //   g6 = bits [10:5]  (6-bit green, 0..63)
    //   b5 = bits [4:0]   (5-bit blue,  0..31)
    // -----------------------------------------------------------------------
    wire [4:0] r5 = d_latch[15:11];
    wire [5:0] g6 = {d_latch[10:8], d_latch[7:5]};
    wire [4:0] b5 = d_latch[4:0];

    // -----------------------------------------------------------------------
    // RGB565 → YCbCr conversion
    //
    // Luminance: Y = (R + G + B) / 3
    //   Approximation: (rgb_sum * 11) >> 5  (11/32 ≈ 1/3)
    //
    // Chrominance: simple threshold comparison (no signed arithmetic)
    //   Compare each channel against Y directly.
    //   Encoding (center = 1 = neutral):
    //     0 = channel is MUCH LESS than Y  (diff < -3)
    //     1 = channel is NEAR Y            (neutral, -3 <= diff < +3)
    //     2 = channel is SOMEWHAT MORE     (+3 <= diff < +8)
    //     3 = channel is MUCH MORE than Y  (diff >= +8)
    // -----------------------------------------------------------------------
    wire [4:0] g5 = g6[5:1];

    // Sum for luminance (max 31+31+31 = 93, fits in 7 bits)
    wire [6:0] rgb_sum = {2'b0, r5} + {2'b0, g5} + {2'b0, b5};

    // Y = rgb_sum / 3 ≈ (rgb_sum * 11) >> 5
    wire [10:0] rgb_sum_x11 = {rgb_sum, 3'b0} + {rgb_sum, 1'b0} + {4'b0, rgb_sum};
    wire [4:0]  y_full = rgb_sum_x11[9:5];   // range 0..31

    // 3-bit stored luma: Y / 4 (range 0..7)
    wire [2:0] y_3bit = y_full[4:2];

    // Chrominance quantization using unsigned comparisons only.
    // For neutral colors (R=G=B): b5 ≈ y_full, so Cb=1 (neutral). Same for Cr.
    // Thresholds chosen so the neutral dead zone is [-3, +3).
    // Signed-difference chroma — fixes white=yellow at high brightness
    wire [5:0] b5_ext   = {1'b0, b5};
    wire [5:0] r5_ext   = {1'b0, r5};
    wire [5:0] y_ext    = {1'b0, y_full};
    wire [5:0] b_above  = (b5_ext > y_ext) ? (b5_ext - y_ext) : 6'd0;
    wire [5:0] b_below  = (y_ext > b5_ext) ? (y_ext - b5_ext) : 6'd0;
    wire [5:0] r_above  = (r5_ext > y_ext) ? (r5_ext - y_ext) : 6'd0;
    wire [5:0] r_below  = (y_ext > r5_ext) ? (y_ext - r5_ext) : 6'd0;

    wire [1:0] cb_2bit = (b_above >= 6'd8) ? 2'd3 :
                         (b_above >= 6'd3) ? 2'd2 :
                         (b_below < 6'd4)  ? 2'd1 :
                                             2'd0;

    wire [1:0] cr_2bit = (r_above >= 6'd8) ? 2'd3 :
                         (r_above >= 6'd3) ? 2'd2 :
                         (r_below < 6'd4)  ? 2'd1 :
                                             2'd0;

    // -----------------------------------------------------------------------
    // Posedge: registered outputs (wr_en, wr_luma, wr_chroma, wr_addr)
    // -----------------------------------------------------------------------
    always @(posedge pclk_in) begin
        wr_en        <= we_reg;
        wr_luma      <= y_3bit;
        wr_chroma    <= {cb_2bit, cr_2bit};
        wr_chroma_en <= ~col_phase;   // write chroma on even columns (col_phase=0)
        wr_addr      <= address;
    end

endmodule
