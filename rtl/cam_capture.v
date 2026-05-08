`timescale 1ns/1ps
// OV7670 RGB565 capture -> YCbCr 4:2:2 quantization (Y3 + Cb2/Cr2).
//
// Pixel byte pairing: same proven technique as the 320 version.
//   - byte_sel toggles on every posedge PCLK while href is high
//   - byte_sel resets on href falling edge (prevents byte-swap drift)
//   - First byte stored in b1, second byte completes the RGB565 word
//
// Color math (BT.601 luma + signed-difference chroma):
//   Y8  = (77*R8 + 150*G8 + 29*B8) >> 8
//   Cb2 = quantize(B8 - Y8) into 4 bins: 0(<-48), 1(-48..-1), 2(0..47), 3(>=48)
//   Cr2 = quantize(R8 - Y8) into 4 bins: same thresholds
//
// Pipeline: b1 captured on byte 1, full RGB565 available on byte 2,
// then YCbCr computed combinationally, outputs registered 1 cycle later.

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

    // Suppress unused parameter warnings
    /* verilator lint_off UNUSED */
    wire _unused = &{1'b0, IMG_WIDTH[9:1], IMG_HEIGHT[9:1]};
    /* verilator lint_on UNUSED */

    // -----------------------------------------------------------------
    // Byte pairing (from 320 version — simple, proven correct)
    // -----------------------------------------------------------------
    reg [7:0] b1;
    reg       byte_sel;
    reg       old_href;
    reg [9:0] pxl_cnt;
    reg [18:0] address;
    reg        col_phase;   // 0 = even column (writes chroma)

    initial begin
        b1         = 8'd0;
        byte_sel   = 1'b0;
        old_href   = 1'b0;
        pxl_cnt    = 10'd0;
        address    = 19'd0;
        col_phase  = 1'b0;
        wr_addr    = 19'd0;
        wr_luma    = 3'd0;
        wr_chroma  = 4'd0;
        wr_en      = 1'b0;
        wr_chroma_en = 1'b0;
        vsync_pulse = 1'b0;
    end

    // -----------------------------------------------------------------
    // RGB565 pixel word (assembled from two bytes)
    // -----------------------------------------------------------------
    wire [15:0] pix16 = {b1, d_in};   // byte1=high, byte2=low

    wire [4:0] r5 = pix16[15:11];
    wire [5:0] g6 = pix16[10:5];
    wire [4:0] b5 = pix16[4:0];

    // Replicate top bits to extend to 8 bits (same trick as original)
    wire [7:0] r8 = {r5, r5[4:2]};
    wire [7:0] g8 = {g6, g6[5:4]};
    wire [7:0] b8 = {b5, b5[4:2]};

    // -----------------------------------------------------------------
    // BT.601 luma: Y = (77R + 150G + 29B) / 256
    // -----------------------------------------------------------------
    wire [15:0] y_acc = ({8'd0, r8} * 16'd77)
                      + ({8'd0, g8} * 16'd150)
                      + ({8'd0, b8} * 16'd29);
    wire [7:0] y8 = y_acc[15:8];
    wire [2:0] y3 = y8[7:5];

    // -----------------------------------------------------------------
    // Chroma: signed B-Y and R-Y quantized into 4 bins
    //   bin 0 : diff < -48   (strong deficit)
    //   bin 1 : diff -48..-1 (mild deficit / neutral)
    //   bin 2 : diff  0..47  (mild positive)
    //   bin 3 : diff >= 48   (strong positive)
    // -----------------------------------------------------------------
    wire signed [9:0] y_s    = $signed({2'b0, y8});
    wire signed [9:0] b_s    = $signed({2'b0, b8});
    wire signed [9:0] r_s    = $signed({2'b0, r8});
    wire signed [9:0] diff_b = b_s - y_s;
    wire signed [9:0] diff_r = r_s - y_s;

    wire [1:0] cb2 = (diff_b >= 10'sd48)  ? 2'd3 :
                     (diff_b >= 10'sd0)   ? 2'd2 :
                     (diff_b >= -10'sd48) ? 2'd1 : 2'd0;

    wire [1:0] cr2 = (diff_r >= 10'sd48)  ? 2'd3 :
                     (diff_r >= 10'sd0)   ? 2'd2 :
                     (diff_r >= -10'sd48) ? 2'd1 : 2'd0;

    // -----------------------------------------------------------------
    // Posedge capture logic — mirrors 320 version structure exactly
    // -----------------------------------------------------------------
    always @(posedge pclk_in) begin
        old_href    <= href;
        vsync_pulse <= 1'b0;
        wr_en       <= 1'b0;

        if (vsync) begin
            // Frame reset
            address    <= 19'd0;
            pxl_cnt    <= 10'd0;
            byte_sel   <= 1'b0;
            col_phase  <= 1'b0;
            vsync_pulse <= 1'b1;

        end else if (href) begin
            if (byte_sel == 1'b0) begin
                // First byte: store high byte
                b1       <= d_in;
                byte_sel <= 1'b1;
                wr_en    <= 1'b0;
            end else begin
                // Second byte: pixel complete -> write to frame buffer
                wr_en        <= 1'b1;
                wr_luma      <= y3;
                wr_chroma    <= {cb2, cr2};
                wr_chroma_en <= ~col_phase;   // chroma on even pixels
                wr_addr      <= address;

                address   <= address + 19'd1;
                col_phase <= ~col_phase;
                pxl_cnt   <= pxl_cnt + 10'd1;
                byte_sel  <= 1'b0;
            end

        end else begin
            // href low: end of line or blanking
            wr_en    <= 1'b0;
            pxl_cnt  <= 10'd0;
            byte_sel <= 1'b0;   // CRITICAL: reset byte phase on line end
        end
    end

endmodule
