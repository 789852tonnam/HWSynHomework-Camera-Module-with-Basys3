`timescale 1ns/1ps
// VGA 640x480 @ 60 Hz timing generator (25 MHz pixel clock).
//
// H: active=640, FP=16, sync=96, BP=48 -> total 800
// V: active=480, FP=10, sync=2,  BP=33 -> total 525
// HSYNC and VSYNC are active-LOW.
//
// rd_addr is combinational. Pipeline: comb(0)+BRAM(1)+filter(2) = 3 cycles.
// Pre-fetch starts 3 cycles early (last 3 H-blanking clocks) so pixel[0]
// arrives exactly when active_d goes high at col 0. No right shift.
//
// line_base counts DOWN (479*640 -> 0) to correct upside-down camera output.

module vga_timing (
    input  wire        clk,
    input  wire        rst,
    output reg  [9:0]  h_count,
    output reg  [9:0]  v_count,
    output wire        hsync,
    output wire        vsync,
    output wire        active_video,
    output wire        fetch_active,
    output wire [18:0] rd_addr
);

    localparam H_ACTIVE = 10'd640;
    localparam H_FP     = 10'd16;
    localparam H_SYNC   = 10'd96;
    localparam H_BP     = 10'd48;
    localparam H_TOTAL  = H_ACTIVE + H_FP + H_SYNC + H_BP;  // 800

    localparam V_ACTIVE = 10'd480;
    localparam V_FP     = 10'd10;
    localparam V_SYNC   = 10'd2;
    localparam V_BP     = 10'd33;
    localparam V_TOTAL  = V_ACTIVE + V_FP + V_SYNC + V_BP;  // 525

    localparam H_SYNC_START = H_ACTIVE + H_FP;             // 656
    localparam H_SYNC_END   = H_ACTIVE + H_FP + H_SYNC;    // 752
    localparam V_SYNC_START = V_ACTIVE + V_FP;             // 490
    localparam V_SYNC_END   = V_ACTIVE + V_FP + V_SYNC;    // 492

    // Pipeline pre-fetch depth
    localparam PIPE = 10'd3;

    initial begin
        h_count = 10'd0;
        v_count = 10'd0;
    end

    // -----------------------------------------------------------------
    // Pixel counters
    // -----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else if (h_count == H_TOTAL - 10'd1) begin
            h_count <= 10'd0;
            v_count <= (v_count == V_TOTAL - 10'd1) ? 10'd0 : v_count + 10'd1;
        end else begin
            h_count <= h_count + 10'd1;
        end
    end

    assign hsync = ~((h_count >= H_SYNC_START) && (h_count < H_SYNC_END));
    assign vsync = ~((v_count >= V_SYNC_START) && (v_count < V_SYNC_END));
    assign active_video = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);

    // -----------------------------------------------------------------
    // line_base counts DOWN to flip image vertically (fix upside-down).
    //   Start: (479-V_OFFSET)*640 — skip V_OFFSET blank rows from camera
    //   Each line: subtract 640 (go one row up in buffer)
    //   Frame end: reset to starting row
    // -----------------------------------------------------------------
    localparam [18:0] LINE_TOP = 19'd479 * 19'd640;

    reg [18:0] line_base;
    initial line_base = LINE_TOP;

    always @(posedge clk) begin
        if (rst) begin
            line_base <= LINE_TOP;
        end else if (h_count == H_TOTAL - 10'd1) begin
            if (v_count == V_TOTAL - 10'd1)
                line_base <= LINE_TOP;
            else if (v_count < V_ACTIVE)         // all 480 active lines
                line_base <= line_base - 19'd640;
        end
    end
    // -----------------------------------------------------------------
    // rd_addr: mirrored + 3-cycle pre-fetch to eliminate structural black
    // pixels at left from BRAM(1)+filter(2)=3 pipeline depth.
    //   Pre-fetch at h_count=797..799 uses next line's base (line_base-640),
    //   filling display pixels 0..2 so active_d can rise at h_count=0.
    //   fetch_active = active_video | prefetch; top.v pipes it through
    //   active_pipe so active_d = active_pipe[2] & active_video is valid
    //   from h_count=0 on all lines except row 0 and row 479 (frame edges).
    //   Coefficient 998 = floor(623*1024/639). Must match PIXEL_SKIP in cam_capture.v.
    // -----------------------------------------------------------------
    localparam [9:0] PIXEL_SKIP     = 10'd16;
    localparam [9:0] VALID_COLS     = 10'd640 - PIXEL_SKIP;  // 624
    localparam [9:0] PREFETCH_START = 10'd797;                 // H_TOTAL - PIPE

    wire in_active = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
    wire prefetch  = (h_count >= PREFETCH_START) && (v_count < V_ACTIVE - 10'd1);

    wire [9:0] pre_h = h_count - PREFETCH_START;
    wire [9:0] act_h = h_count + PIPE;
    wire [9:0] eff_h = prefetch ? pre_h : act_h;

    wire [18:0] next_line_base = line_base - 19'd640;
    wire [18:0] eff_base = prefetch ? next_line_base : line_base;

    wire [19:0] h_scaled = ({10'd0, eff_h} * 20'd998) >> 10;
    wire [9:0]  mirror_x = (VALID_COLS - 10'd1) - h_scaled[9:0];

    assign fetch_active = in_active || prefetch;
    assign rd_addr = fetch_active ? (eff_base + {9'd0, mirror_x}) : 19'd0;

endmodule

