`timescale 1ns/1ps
// top.v
// Top-level module for the FPGA real-time video pipeline.
// Target: Digilent Basys 3 (Xilinx Artix-7 XC7A35T)
//
// YCbCr 4:2:2 encoding (Y3:Cb2:Cr2):
//   - Luma buffer:   307,200 × 3 bits = 30 BRAMs
//   - Chroma buffer: 153,600 × 4 bits = 20 BRAMs
//   - Total: 50/50 BRAMs (100% utilization)
//
// Connections:
//   - clk_wiz_main: 100 MHz -> 25 MHz (VGA) and 24 MHz (camera XCLK)
//   - cam_config: configures OV7670 via SCCB (58-entry ROM)
//   - cam_capture: captures OV7670 pixel data, converts RGB565→YCbCr
//   - frame_buffer: split luma + chroma dual-port BRAMs
//   - filter_pipeline: reads luma+chroma, applies selected filter (@ clk_25)
//   - vga_timing: generates HSYNC/VSYNC, active_video, rd_addr (@ clk_25)
//   - debouncer: debounces switches and BTNC
//   - cdc_pulse_sync: crosses VSYNC pulse from PCLK to clk_25 domain for LED
//
// LED diagnostic map:
//   LD[15]    = cfg_done              (solid when camera config finished)
//   LD[14]    = led_frame_toggle      (toggles each VSYNC = frame-rate indicator)
//   LD[13:8]  = reg_writes_done[5:0] (counts to 58 during boot)
//   LD[7:4]   = sw74                  (edge threshold passthrough)
//   LD[3:2]   = sw32                  (color isolation channel passthrough)
//   LD[1:0]   = sw_mode               (filter select indicator)
//
// Switch mapping:
//   SW[1:0]  = sw_mode          filter select
//   SW[3:2]  = sw32             color isolation channel
//   SW[7:4]  = sw74             edge filter threshold
//   SW[8]    = sw_test_pattern  OV7670 SCCB color-bar test mode
//   SW[9]    = tp_enable        FPGA test-pattern bypass
//   SW[15:10]= (unused, reserved for future)

module top #(
    parameter DEBOUNCE_N    = 20,       // debounce counter width (override for sim)
    parameter CAM_RST_HOLD  = 625000,   // cam_config RST_HOLD (override for sim)
    parameter CAM_POST_RST  = 250000,   // cam_config POST_RST  (was 62500; now 10 ms)
    parameter CAM_SOFT_WAIT = 750000,   // cam_config SOFT_RST_WAIT (was 62500; now 30 ms)
    parameter CAM_REG_GAP   = 2500      // cam_config REG_GAP (~100 us between ROM writes)
) (
    // Board clock
    input  wire        clk_100,     // W5 — 100 MHz

    // VGA outputs
    output wire        vga_hsync,   // P19
    output wire        vga_vsync,   // R19
    output wire [3:0]  vga_r,       // G19,H19,J19,N19
    output wire [3:0]  vga_g,       // J17,H17,G17,D17
    output wire [3:0]  vga_b,       // N18,L18,K18,J18

    // OV7670 camera
    output wire        cam_xclk,    // C15 — 24 MHz clock to camera
    output wire        cam_rst_n,   // P18 — camera reset (active low)
    output wire        cam_pwdn,    // R18 — camera power down (keep 0)
    output wire        cam_scl,     // A14 — SCCB clock
    inout  wire        cam_sda,     // A15 — SCCB data (bi-dir open drain)
    input  wire        cam_pclk,    // A16 — camera pixel clock
    input  wire        cam_href,    // A17 — horizontal reference
    input  wire        cam_vsync,   // B15 — vertical sync
    input  wire [7:0]  cam_d,       // P17..B16 — pixel data

    // User I/O
    input  wire [15:0] sw,          // slide switches
    input  wire        btnc,        // center button (reset)
    output wire [15:0] led          // LEDs
);

    // -----------------------------------------------------------------------
    // Clock generation
    // -----------------------------------------------------------------------
    wire clk_25, clk_24, mmcm_locked;

    clk_wiz_main u_clkwiz (
        .clk_100 (clk_100),
        .clk_25  (clk_25),
        .clk_24  (clk_24),
        .locked  (mmcm_locked)
    );

    assign cam_xclk = clk_24;

    // -----------------------------------------------------------------------
    // Debouncer for switches and center button
    // -----------------------------------------------------------------------
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

    // System reset: MMCM not locked or button pressed
    wire sys_rst = btnc_db | ~mmcm_locked;

    // -----------------------------------------------------------------------
    // Switch mapping
    // -----------------------------------------------------------------------
    wire [1:0] sw_mode          = sw_db[1:0];    // SW[1:0]: filter select
    wire [1:0] sw32             = sw_db[3:2];    // SW[3:2]: color isolation channel
    wire [3:0] sw74             = sw_db[7:4];    // SW[7:4]: edge threshold
    wire       sw_test_pattern  = sw_db[8];      // SW[8]:   OV7670 SCCB color-bar test mode
    wire       tp_enable        = sw_db[9];      // SW[9]:   FPGA test-pattern bypass (diagnostic)
    // SW[15:10]: unused (reserved)

    // -----------------------------------------------------------------------
    // Camera configuration (SCCB sequencer)
    // -----------------------------------------------------------------------
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
        .clk_div_run      (11'd125),
        .cam_rst_n        (cam_rst_n),
        .cam_pwdn         (cam_pwdn),
        .scl              (cam_scl),
        .sda              (cam_sda),
        .test_pattern_en  (sw_test_pattern),
        .cfg_done         (cfg_done),
        .reg_writes_done  (reg_writes_done),
        .successful_xacts (successful_xacts)
    );

    // -----------------------------------------------------------------------
    // Camera capture (pclk domain) — RGB565 → YCbCr conversion
    // -----------------------------------------------------------------------
    wire [18:0] fb_wr_addr;
    wire [2:0]  fb_wr_luma;
    wire [3:0]  fb_wr_chroma;
    wire        fb_wr_en;
    wire        fb_wr_chroma_en;
    wire        vsync_pulse_pclk;   // one-cycle pulse per frame @ PCLK

    cam_capture #(
        .IMG_WIDTH  (640),
        .IMG_HEIGHT (480)
    ) u_capture (
        .pclk_in      (cam_pclk),
        .d_in         (cam_d),
        .href         (cam_href),
        .vsync        (cam_vsync),
        .wr_addr      (fb_wr_addr),
        .wr_luma      (fb_wr_luma),
        .wr_chroma    (fb_wr_chroma),
        .wr_en        (fb_wr_en),
        .wr_chroma_en (fb_wr_chroma_en),
        .vsync_pulse  (vsync_pulse_pclk)
    );

    // -----------------------------------------------------------------------
    // Test pattern injector (bypasses camera when SW[9] = 1)
    // Generates YCbCr color bars: Red, Green, Blue vertical stripes.
    //
    // Chroma encoding: 0=strong deficit, 1=neutral, 2=moderate, 3=strong
    //   RED:   Y=4, Cb=1(neutral), Cr=3(strong red)    → {Cb=01, Cr=11}
    //   GREEN: Y=5, Cb=0(blue deficit), Cr=0(red deficit) → {Cb=00, Cr=00}
    //   BLUE:  Y=2, Cb=3(strong blue), Cr=1(neutral)   → {Cb=11, Cr=01}
    // -----------------------------------------------------------------------
    reg  [9:0]  tp_col;
    reg  [9:0]  tp_row;
    reg  [18:0] tp_wr_addr;
    reg  [2:0]  tp_wr_luma;
    reg  [3:0]  tp_wr_chroma;
    reg         tp_wr_en;
    reg         tp_wr_chroma_en;

    always @(posedge cam_pclk) begin
        if (sys_rst) begin
            tp_col <= 10'd0;
            tp_row <= 10'd0;
        end else begin
            if (tp_col == 10'd639) begin
                tp_col <= 10'd0;
                if (tp_row == 10'd479)
                    tp_row <= 10'd0;
                else
                    tp_row <= tp_row + 10'd1;
            end else begin
                tp_col <= tp_col + 10'd1;
            end
        end
    end

    always @(*) begin
        tp_wr_addr = tp_row * 19'd640 + {9'd0, tp_col};
        tp_wr_chroma_en = ~tp_col[0]; // write chroma on even columns
        tp_wr_en = 1'b1;

        if (tp_col < 10'd213) begin
            // RED bar: medium bright, strong red, neutral blue
            tp_wr_luma   = 3'd4;
            tp_wr_chroma = 4'b01_11;  // Cb=1(neutral), Cr=3(strong red)
        end else if (tp_col < 10'd426) begin
            // GREEN bar: bright, both deficits = green
            tp_wr_luma   = 3'd5;
            tp_wr_chroma = 4'b00_00;  // Cb=0(blue deficit), Cr=0(red deficit)
        end else begin
            // BLUE bar: darker, strong blue, neutral red
            tp_wr_luma   = 3'd2;
            tp_wr_chroma = 4'b11_01;  // Cb=3(strong blue), Cr=1(neutral)
        end
    end

    // Mux: tp_enable=1 -> test pattern drives BRAM write port; =0 -> camera path
    wire [18:0] fb_wr_addr_mux       = tp_enable ? tp_wr_addr       : fb_wr_addr;
    wire [2:0]  fb_wr_luma_mux       = tp_enable ? tp_wr_luma       : fb_wr_luma;
    wire [3:0]  fb_wr_chroma_mux     = tp_enable ? tp_wr_chroma     : fb_wr_chroma;
    wire        fb_wr_en_mux         = tp_enable ? tp_wr_en         : fb_wr_en;
    wire        fb_wr_chroma_en_mux  = tp_enable ? tp_wr_chroma_en  : fb_wr_chroma_en;

    // -----------------------------------------------------------------------
    // Frame buffer (split luma + chroma dual-port BRAMs)
    // wr_clk is always cam_pclk — no clock mux required.
    // -----------------------------------------------------------------------
    wire [18:0] fb_rd_addr;
    wire [2:0]  fb_rd_luma;
    wire [3:0]  fb_rd_chroma;

    frame_buffer u_fb (
        .wr_clk       (cam_pclk),
        .wr_en        (fb_wr_en_mux),
        .wr_addr      (fb_wr_addr_mux),
        .wr_luma      (fb_wr_luma_mux),
        .wr_chroma    (fb_wr_chroma_mux),
        .wr_chroma_en (fb_wr_chroma_en_mux),
        .rd_clk       (clk_25),
        .rd_addr      (fb_rd_addr),
        .rd_luma      (fb_rd_luma),
        .rd_chroma    (fb_rd_chroma)
    );

    // -----------------------------------------------------------------------
    // VGA timing
    // -----------------------------------------------------------------------
    wire [9:0]  h_count, v_count;
    wire        active_video;
    wire        h_edge, v_edge;

    vga_timing u_vga (
        .clk         (clk_25),
        .rst         (sys_rst),
        .hsync       (vga_hsync),
        .vsync       (vga_vsync),
        .h_count     (h_count),
        .v_count     (v_count),
        .active_video(active_video),
        .rd_addr     (fb_rd_addr)
    );

    assign h_edge = (h_count == 10'd0) | (h_count == 10'd639);
    assign v_edge = (v_count < 10'd2) | (v_count >= 10'd479);

    // -----------------------------------------------------------------------
    // Filter pipeline (YCbCr input, RGB444 output)
    // -----------------------------------------------------------------------
    wire [11:0] filter_out;

    filter_pipeline #(.WIDTH(640)) u_filt (
        .clk       (clk_25),
        .rst       (sys_rst),
        .fb_luma   (fb_rd_luma),
        .fb_chroma (fb_rd_chroma),
        .h_count   (h_count),
        .v_count   (v_count),
        .pix_valid (active_video),
        .sw_mode   (sw_mode),
        .sw32      (sw32),
        .sw74      (sw74),
        .h_edge    (h_edge),
        .v_edge    (v_edge),
        .rgb444_out(filter_out)
    );

    // -----------------------------------------------------------------------
    // VGA RGB output (gate with active_video, 1-cycle delayed to match pipeline)
    // -----------------------------------------------------------------------
    reg active_video_d;
    always @(posedge clk_25) active_video_d <= active_video;

    assign vga_r = active_video_d ? filter_out[11:8] : 4'h0;
    assign vga_g = active_video_d ? filter_out[7:4]  : 4'h0;
    assign vga_b = active_video_d ? filter_out[3:0]  : 4'h0;

    // -----------------------------------------------------------------------
    // CDC: VSYNC pulse from PCLK domain -> clk_25 domain (for LED toggle)
    // -----------------------------------------------------------------------
    wire vsync_pulse_25;

    cdc_pulse_sync u_cdc (
        .clk_src    (cam_pclk),
        .clk_dst    (clk_25),
        .rst_src    (1'b0),
        .rst_dst    (sys_rst),
        .pulse_in   (vsync_pulse_pclk),
        .pulse_out  (vsync_pulse_25)
    );

    // LED frame counter: toggles each VSYNC
    reg led_frame_toggle;
    always @(posedge clk_25) begin
        if (sys_rst)
            led_frame_toggle <= 1'b0;
        else if (vsync_pulse_25)
            led_frame_toggle <= ~led_frame_toggle;
    end

    // -----------------------------------------------------------------------
    // LED outputs
    //   LD[15]    = cfg_done
    //   LD[14]    = led_frame_toggle
    //   LD[13:8]  = reg_writes_done[5:0]
    //   LD[7:4]   = sw74
    //   LD[3:2]   = sw32
    //   LD[1:0]   = sw_mode
    // -----------------------------------------------------------------------
    assign led[15]   = cfg_done;
    assign led[14]   = led_frame_toggle;
    assign led[13:8] = reg_writes_done;
    assign led[7:4]  = sw74;
    assign led[3:2]  = sw32;
    assign led[1:0]  = sw_mode;

endmodule
