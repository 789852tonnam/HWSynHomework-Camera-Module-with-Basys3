`timescale 1ns/1ps
// OV7670 RGB565 capture and YCbCr 4:2:2 quantization (Y3 + Cb2/Cr2).
//
// Camera signals are sampled on the falling edge of PCLK (data is stable in
// the middle of the high half per the OV7670 datasheet timing diagram).
// On each href-active line two PCLK cycles assemble one RGB565 pixel; we_reg
// pulses one cycle after the second byte arrives. Address resets on VSYNC.
//
// Color math (BT.601 luma + signed-difference chroma):
//   Y8  = (77*R8 + 150*G8 + 29*B8) >> 8                    (~0.299 R + 0.587 G + 0.114 B)
//   Cb2 = quantize(B8 - Y8) into 4 bins symmetric around 0
//   Cr2 = quantize(R8 - Y8) into 4 bins symmetric around 0
//
// Chroma bin layout (signed difference d in 8-bit-equivalent units):
//   d >= +48   -> 3  (strong)
//   d >= +16   -> 2  (mild)
//   d >= -16   -> 1  (mild deficit)
//   else       -> 0  (strong deficit)
// The decoder in ycbcr_to_rgb444 maps each bin back to a small signed offset.

module cam_capture #(
    parameter IMG_WIDTH  = 640,
    parameter IMG_HEIGHT = 480
) (
    input  wire        pclk_in,

    input  wire [7:0]  d_in,
    input  wire        href,
    input  wire        vsync,

    output reg  [18:0] wr_addr,
    output reg  [2:0]  wr_luma,
    output reg  [3:0]  wr_chroma,
    output reg         wr_en,
    output reg         wr_chroma_en,
    output reg         vsync_pulse
);

    // Avoid synth warnings on unused params (kept for top-level documentation)
    /* verilator lint_off UNUSED */
    wire _unused = &{1'b0, IMG_WIDTH[0], IMG_HEIGHT[0]};
    /* verilator lint_on UNUSED */

    // -----------------------------------------------------------------
    // Negedge latches: sample camera bus at stable point
    // -----------------------------------------------------------------
    reg [7:0] latched_d;
    reg       latched_href, latched_vsync;

    initial begin
        latched_d     = 8'd0;
        latched_href  = 1'b0;
        latched_vsync = 1'b0;
    end

    always @(negedge pclk_in) begin
        latched_d     <= d_in;
        latched_href  <= href;
        latched_vsync <= vsync;
    end

    // -----------------------------------------------------------------
    // Posedge: byte pairing, address counter, vsync detection
    // -----------------------------------------------------------------
    reg [15:0] d_latch;
    reg [6:0]  href_last;
    reg [18:0] address;
    reg        we_reg;
    reg        col_phase;     // toggles each pixel; 0 = even column

    initial begin
        d_latch       = 16'd0;
        href_last     = 7'd0;
        address       = 19'd0;
        we_reg        = 1'b0;
        col_phase     = 1'b0;
        wr_addr       = 19'd0;
        wr_luma       = 3'd0;
        wr_chroma     = 4'd0;
        wr_en         = 1'b0;
        wr_chroma_en  = 1'b0;
        vsync_pulse   = 1'b0;
    end

    always @(posedge pclk_in) begin
        vsync_pulse <= 1'b0;
        we_reg      <= 1'b0;

        // Address advances on the cycle after each completed pixel
        if (we_reg) begin
            address   <= address + 19'd1;
            col_phase <= ~col_phase;
        end

        // Shift in pixel bytes while line is active
        if (latched_href)
            d_latch <= {d_latch[7:0], latched_d};

        if (latched_vsync) begin
            address     <= 19'd0;
            href_last   <= 7'd0;
            vsync_pulse <= 1'b1;
            col_phase   <= 1'b0;
        end else if (href_last[0]) begin
            we_reg    <= 1'b1;     // second byte just arrived -> pixel complete
            href_last <= 7'd0;
        end else begin
            href_last <= {href_last[5:0], latched_href};
        end
    end

    // -----------------------------------------------------------------
    // RGB565 -> RGB888 (replicate top bits to fill — gives clean 0..255)
    // -----------------------------------------------------------------
    wire [4:0] r5 = d_latch[15:11];
    wire [5:0] g6 = d_latch[10:5];
    wire [4:0] b5 = d_latch[4:0];

    wire [7:0] r8 = {r5, r5[4:2]};
    wire [7:0] g8 = {g6, g6[5:4]};
    wire [7:0] b8 = {b5, b5[4:2]};

    // -----------------------------------------------------------------
    // BT.601 luma:  Y = (77 R + 150 G + 29 B) / 256
    // Max = 256 * 255 = 65280 -> 16-bit accumulator
    // -----------------------------------------------------------------
    wire [15:0] y_acc = {8'd0, r8} * 16'd77
                      + {8'd0, g8} * 16'd150
                      + {8'd0, b8} * 16'd29;
    wire [7:0]  y8 = y_acc[15:8];
    wire [2:0]  y3 = y8[7:5];

    // -----------------------------------------------------------------
    // Chroma: signed B-Y and R-Y, quantized into 4 symmetric bins
    // -----------------------------------------------------------------
    wire signed [9:0] y_s    = $signed({2'b0, y8});
    wire signed [9:0] b_s    = $signed({2'b0, b8});
    wire signed [9:0] r_s    = $signed({2'b0, r8});
    wire signed [9:0] diff_b = b_s - y_s;
    wire signed [9:0] diff_r = r_s - y_s;

    wire [1:0] cb2 = (diff_b >=  10'sd48) ? 2'd3 :
                     (diff_b >=  10'sd16) ? 2'd2 :
                     (diff_b >= -10'sd16) ? 2'd1 : 2'd0;

    wire [1:0] cr2 = (diff_r >=  10'sd48) ? 2'd3 :
                     (diff_r >=  10'sd16) ? 2'd2 :
                     (diff_r >= -10'sd16) ? 2'd1 : 2'd0;

    // -----------------------------------------------------------------
    // Registered outputs
    // -----------------------------------------------------------------
    always @(posedge pclk_in) begin
        wr_en        <= we_reg;
        wr_luma      <= y3;
        wr_chroma    <= {cb2, cr2};
        wr_chroma_en <= ~col_phase;     // chroma writes on even columns
        wr_addr      <= address;
    end

endmodule
