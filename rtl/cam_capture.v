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
// PIXEL_SKIP camera pixels at the start of each HREF line are discarded
// (OV7670 HREF startup glitch). fb[0] per row = first valid camera pixel.
// PIXEL_SKIP must be even to preserve chroma phase alignment.

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

    // Skip first N camera pixels per line (HREF startup glitch). Must be even.
    // Tune upward if black/garbage visible on right side of display.
    localparam [9:0] PIXEL_SKIP = 10'd16;
    localparam [9:0] VALID_COLS = 10'd640 - PIXEL_SKIP;  // 624

    // -----------------------------------------------------------------
    // Byte pairing
    // -----------------------------------------------------------------
    reg [7:0]  b1;
    reg        byte_sel;
    reg        old_href;
    reg [9:0]  pxl_cnt;
    reg [18:0] row_base;   // base address of current fb row (0, 640, 1280, ...)
    reg [9:0]  write_col;  // column index within row (0..VALID_COLS-1)

    initial begin
        b1           = 8'd0;
        byte_sel     = 1'b0;
        old_href     = 1'b0;
        pxl_cnt      = 10'd0;
        row_base     = 19'd0;
        write_col    = 10'd0;
        wr_addr      = 19'd0;
        wr_luma      = 3'd0;
        wr_chroma    = 4'd0;
        wr_en        = 1'b0;
        wr_chroma_en = 1'b0;
        vsync_pulse  = 1'b0;
    end

    // -----------------------------------------------------------------
    // RGB565 pixel word (assembled from two bytes)
    // -----------------------------------------------------------------
    wire [15:0] pix16 = {b1, d_in};   // byte1=high, byte2=low

    wire [4:0] r5 = pix16[15:11];
    wire [5:0] g6 = pix16[10:5];
    wire [4:0] b5 = pix16[4:0];

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
    // Capture logic
    // -----------------------------------------------------------------
    always @(posedge pclk_in) begin
        old_href    <= href;
        vsync_pulse <= 1'b0;
        wr_en       <= 1'b0;

        if (vsync) begin
            pxl_cnt     <= 10'd0;
            byte_sel    <= 1'b0;
            write_col   <= 10'd0;
            row_base    <= 19'd0;
            vsync_pulse <= 1'b1;

        end else if (href) begin
            if (byte_sel == 1'b0) begin
                b1       <= d_in;
                byte_sel <= 1'b1;
            end else begin
                // Write valid pixels: skip first PIXEL_SKIP, cap at VALID_COLS per row
                if (pxl_cnt >= PIXEL_SKIP && write_col < VALID_COLS) begin
                    wr_en        <= 1'b1;
                    wr_luma      <= y3;
                    wr_chroma    <= {cb2, cr2};
                    wr_chroma_en <= (write_col[0] == 1'b0);  // chroma on even write_col
                    wr_addr      <= row_base + {9'd0, write_col};
                    write_col    <= write_col + 10'd1;
                end
                pxl_cnt  <= pxl_cnt + 10'd1;
                byte_sel <= 1'b0;
            end

        end else begin
            pxl_cnt   <= 10'd0;
            byte_sel  <= 1'b0;
            write_col <= 10'd0;
            if (old_href == 1'b1)
                row_base <= row_base + 19'd640;
        end
    end
endmodule
