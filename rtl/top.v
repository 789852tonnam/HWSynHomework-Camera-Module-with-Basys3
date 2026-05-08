`timescale 1ns/1ps
// Top-level: real-time 640x480 video pipeline on Basys 3 + OV7670.
//
// Data path:
//   OV7670 (RGB565 @ pclk)
//     -> cam_capture                  (RGB565 -> YCbCr 4:2:2, Y3+Cb2/Cr2)
//     -> frame_buffer                 (split luma 30 BRAMs + chroma 20 BRAMs)
//     -> filter_pipeline @ clk_25     (RAW / INVERT / COLOR_ISO / EDGE)
//     -> VGA pins (RGB444)
//
// Clocks:
//   clk_100 (board)  -> clk_wiz_main -> clk_25 (VGA pixel) and clk_24 (cam XCLK)
//
// Switch mapping:
//   SW[1:0]  filter mode
//   SW[3:2]  color isolation channel
//   SW[7:4]  Sobel edge threshold
//   SW[8]    OV7670 internal color-bar test pattern (SCCB writes)
//   SW[9]    FPGA-side test pattern bypass (replaces camera writes)
//   SW[15:10] reserved
//
// LED map:
//   LD[15]    cfg_done
//   LD[14]    led_frame_toggle (toggles each VSYNC)
//   LD[13:8]  reg_writes_done[5:0]
//   LD[7:4]   sw74 passthrough
//   LD[3:2]   sw32 passthrough
//   LD[1:0]   sw_mode passthrough

module top #(
    parameter integer DEBOUNCE_N    = 20,
    parameter integer CAM_RST_HOLD  = 625000,
    parameter integer CAM_POST_RST  = 250000,
    parameter integer CAM_SOFT_WAIT = 750000,
    parameter integer CAM_REG_GAP   = 2500
) (
    input  wire        clk_100,

    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,

    output wire        cam_xclk,
    output wire        cam_rst_n,
    output wire        cam_pwdn,
    output wire        cam_scl,
    inout  wire        cam_sda,
    input  wire        cam_pclk,
    input  wire        cam_href,
    input  wire        cam_vsync,
    input  wire [7:0]  cam_d,

    input  wire [15:0] sw,
    input  wire        btnc,
    output wire [15:0] led
);

    // -----------------------------------------------------------------
    // Clocks
    // -----------------------------------------------------------------
    wire clk_25, clk_24, mmcm_locked;

    clk_wiz_main u_clkwiz (
        .clk_100 (clk_100),
        .clk_25  (clk_25),
        .clk_24  (clk_24),
        .locked  (mmcm_locked)
    );

    assign cam_xclk = clk_24;

    // -----------------------------------------------------------------
    // Debounce switches and center button (clk_25 domain)
    // -----------------------------------------------------------------
    wire [15:0] sw_db;
    wire        btnc_db;

    debouncer #(.W(16), .N(DEBOUNCE_N)) u_sw_db (
        .clk    (clk_25),
        .sw_in  (sw),
        .sw_out (sw_db)
    );

    debouncer #(.W(1), .N(DEBOUNCE_N)) u_btn_db (
        .clk    (clk_25),
        .sw_in  (btnc),
        .sw_out (btnc_db)
    );

    wire sys_rst = btnc_db | ~mmcm_locked;

    wire [1:0] sw_mode         = sw_db[1:0];
    wire [1:0] sw32            = sw_db[3:2];
    wire [3:0] sw74            = sw_db[7:4];
    wire       sw_test_pattern = sw_db[8];
    wire       tp_enable       = sw_db[9];

    // -----------------------------------------------------------------
    // Camera configuration (SCCB)
    // -----------------------------------------------------------------
    wire        cfg_done;
    wire [6:0]  reg_writes_done;
    wire [6:0]  successful_xacts;

    cam_config #(
        .RST_HOLD      (CAM_RST_HOLD),
        .POST_RST      (CAM_POST_RST),
        .SOFT_RST_WAIT (CAM_SOFT_WAIT),
        .REG_GAP       (CAM_REG_GAP),
        .OV7670_ID     (8'h42)
    ) u_camcfg (
        .clk              (clk_25),
        .rst              (sys_rst),
        .cam_rst_n        (cam_rst_n),
        .cam_pwdn         (cam_pwdn),
        .scl              (cam_scl),
        .sda              (cam_sda),
        .test_pattern_en  (sw_test_pattern),
        .cfg_done         (cfg_done),
        .reg_writes_done  (reg_writes_done),
        .successful_xacts (successful_xacts)
    );

    // -----------------------------------------------------------------
    // Camera capture (cam_pclk domain) -> YCbCr 4:2:2
    // -----------------------------------------------------------------
    wire [18:0] cap_addr;
    wire [2:0]  cap_luma;
    wire [3:0]  cap_chroma;
    wire        cap_we;
    wire        cap_chroma_we;
    wire        vsync_pulse_pclk;

    cam_capture #(
        .IMG_WIDTH  (640),
        .IMG_HEIGHT (480)
    ) u_capture (
        .pclk_in      (cam_pclk),
        .d_in         (cam_d),
        .href         (cam_href),
        .vsync        (cam_vsync),
        .wr_addr      (cap_addr),
        .wr_luma      (cap_luma),
        .wr_chroma    (cap_chroma),
        .wr_en        (cap_we),
        .wr_chroma_en (cap_chroma_we),
        .vsync_pulse  (vsync_pulse_pclk)
    );

    // -----------------------------------------------------------------
    // FPGA-side test pattern (SW[9]) — three vertical color bars in YCbCr
    //   Red   bar: Y=4, {Cb2=01 (mild blue deficit), Cr2=11 (strong red)}
    //   Green bar: Y=5, {Cb2=00, Cr2=00}                        (both deficit)
    //   Blue  bar: Y=2, {Cb2=11 (strong blue), Cr2=01 (mild)}
    // -----------------------------------------------------------------
    reg  [9:0]  tp_col, tp_row;
    reg  [18:0] tp_addr;
    reg  [2:0]  tp_luma;
    reg  [3:0]  tp_chroma;
    reg         tp_we, tp_chroma_we;

    always @(posedge cam_pclk) begin
        if (sys_rst) begin
            tp_col <= 10'd0;
            tp_row <= 10'd0;
        end else if (tp_col == 10'd639) begin
            tp_col <= 10'd0;
            tp_row <= (tp_row == 10'd479) ? 10'd0 : tp_row + 10'd1;
        end else begin
            tp_col <= tp_col + 10'd1;
        end
    end

    always @(*) begin
        tp_addr      = tp_row * 19'd640 + {9'd0, tp_col};
        tp_we        = 1'b1;
        tp_chroma_we = ~tp_col[0];

        if (tp_col < 10'd213) begin
            tp_luma   = 3'd4;
            tp_chroma = 4'b01_11;
        end else if (tp_col < 10'd426) begin
            tp_luma   = 3'd5;
            tp_chroma = 4'b00_00;
        end else begin
            tp_luma   = 3'd2;
            tp_chroma = 4'b11_01;
        end
    end

    wire [18:0] fb_wr_addr      = tp_enable ? tp_addr      : cap_addr;
    wire [2:0]  fb_wr_luma      = tp_enable ? tp_luma      : cap_luma;
    wire [3:0]  fb_wr_chroma    = tp_enable ? tp_chroma    : cap_chroma;
    wire        fb_wr_en        = tp_enable ? tp_we        : cap_we;
    wire        fb_wr_chroma_en = tp_enable ? tp_chroma_we : cap_chroma_we;

    // -----------------------------------------------------------------
    // Frame buffer (write @ cam_pclk, read @ clk_25)
    // -----------------------------------------------------------------
    wire [18:0] fb_rd_addr;
    wire [2:0]  fb_rd_luma;
    wire [3:0]  fb_rd_chroma;

    frame_buffer u_fb (
        .wr_clk       (cam_pclk),
        .wr_en        (fb_wr_en),
        .wr_addr      (fb_wr_addr),
        .wr_luma      (fb_wr_luma),
        .wr_chroma    (fb_wr_chroma),
        .wr_chroma_en (fb_wr_chroma_en),
        .rd_clk       (clk_25),
        .rd_addr      (fb_rd_addr),
        .rd_luma      (fb_rd_luma),
        .rd_chroma    (fb_rd_chroma)
    );

    // -----------------------------------------------------------------
    // VGA timing
    // -----------------------------------------------------------------
    wire [9:0]  h_count, v_count;
    wire        active_video;

    vga_timing u_vga (
        .clk          (clk_25),
        .rst          (sys_rst),
        .hsync        (vga_hsync),
        .vsync        (vga_vsync),
        .h_count      (h_count),
        .v_count      (v_count),
        .active_video (active_video),
        .rd_addr      (fb_rd_addr)
    );

    wire h_edge = (h_count == 10'd0) | (h_count >= 10'd638);
    wire v_edge = (v_count <  10'd2) | (v_count >= 10'd479);

    // -----------------------------------------------------------------
    // Filter pipeline
    // -----------------------------------------------------------------
    wire [11:0] filter_out;

    filter_pipeline #(.WIDTH(640)) u_filt (
        .clk        (clk_25),
        .rst        (sys_rst),
        .fb_luma    (fb_rd_luma),
        .fb_chroma  (fb_rd_chroma),
        .h_count    (h_count),
        .v_count    (v_count),
        .pix_valid  (active_video),
        .sw_mode    (sw_mode),
        .sw32       (sw32),
        .sw74       (sw74),
        .h_edge     (h_edge),
        .v_edge     (v_edge),
        .rgb444_out (filter_out)
    );

    // -----------------------------------------------------------------
    // VGA output gating
    // Pipeline depth from h_count to filter_out:
    //   vga_timing rd_addr reg (1) + frame_buffer BRAM (1) + filter_pipeline (2) = 4
    // Delay active_video by 4 cycles to gate output cleanly.
    // -----------------------------------------------------------------
    reg [3:0] active_pipe;
    always @(posedge clk_25) begin
        if (sys_rst) active_pipe <= 4'd0;
        else         active_pipe <= {active_pipe[2:0], active_video};
    end
    wire active_d = active_pipe[3];

    assign vga_r = active_d ? filter_out[11:8] : 4'h0;
    assign vga_g = active_d ? filter_out[7:4]  : 4'h0;
    assign vga_b = active_d ? filter_out[3:0]  : 4'h0;

    // -----------------------------------------------------------------
    // VSYNC pulse CDC: cam_pclk -> clk_25, drives a frame-rate LED
    // -----------------------------------------------------------------
    wire vsync_pulse_25;

    cdc_pulse_sync u_cdc (
        .clk_src   (cam_pclk),
        .clk_dst   (clk_25),
        .rst_src   (1'b0),
        .rst_dst   (sys_rst),
        .pulse_in  (vsync_pulse_pclk),
        .pulse_out (vsync_pulse_25)
    );

    reg led_frame_toggle;
    always @(posedge clk_25) begin
        if (sys_rst)             led_frame_toggle <= 1'b0;
        else if (vsync_pulse_25) led_frame_toggle <= ~led_frame_toggle;
    end

    /* verilator lint_off UNUSED */
    wire _unused_xacts = &{1'b0, successful_xacts};
    /* verilator lint_on UNUSED */

    assign led[15]   = cfg_done;
    assign led[14]   = led_frame_toggle;
    assign led[13:8] = reg_writes_done[5:0];
    assign led[7:4]  = sw74;
    assign led[3:2]  = sw32;
    assign led[1:0]  = sw_mode;

endmodule
