`timescale 1ns/1ps
// 3-line circular shift buffer for a 3x3 Sobel neighbourhood (luma only).
//
// Three WIDTH x 3-bit distributed RAMs hold rows N-2, N-1, N (current).
// Spatial labels follow image convention:
//   top  = row above center  = row N-2  (oldest complete)
//   mid  = center row        = row N-1  (most recent complete)
//   bot  = row below center  = row N    (currently being written)
//
// The Sobel pixel under test is (row N-1, col h-1). The 3x3 window samples
// columns (h-2, h-1, h) of the three rows; col_r = h_count and col_l/c are
// h_count clamped on subtraction. The window output appears 1 cycle after
// the addresses are presented (registered read).
//
// HAZARD HANDLING:
// Reading bot_r from lb[bot_idx][h_count] would return the value present
// BEFORE this cycle's write (row N-3 leftover from the previous frame). To
// get the just-arrived pixel we forward pix_in into bot_r directly, since
// col_r is always equal to h_count in this design. bot_l and bot_c read
// columns h-2 and h-1 which were written 2 and 1 cycles ago respectively
// and are already committed.
//
// Display offset: the Sobel center at col h-1 emerges at VGA column h+1
// (after the filter_pipeline output register), giving a ~2-pixel rightward
// and 1-row downward shift in edge mode. Invisible at 640x480.

module line_buffer3 #(
    parameter integer WIDTH = 640
) (
    input  wire        clk,
    input  wire        rst,

    input  wire [2:0]  pix_in,
    input  wire        pix_valid,
    input  wire [9:0]  h_count,
    input  wire [9:0]  v_count,

    output reg  [2:0]  top_l, top_c, top_r,
    output reg  [2:0]  mid_l, mid_c, mid_r,
    output reg  [2:0]  bot_l, bot_c, bot_r
);

    /* verilator lint_off UNUSED */
    wire _unused = &{1'b0, v_count};
    /* verilator lint_on UNUSED */

    (* ram_style = "distributed" *)
    reg [2:0] lb [0:2][0:WIDTH-1];

    integer i, j;
    initial begin
        for (i = 0; i < 3; i = i + 1)
            for (j = 0; j < WIDTH; j = j + 1)
                lb[i][j] = 3'd0;
    end

    // wr_idx = which buffer is currently being written this row (= bot row).
    reg [1:0] wr_idx;
    initial wr_idx = 2'd0;

    wire [1:0] top_idx = (wr_idx == 2'd2) ? 2'd0 : wr_idx + 2'd1;   // (wr+1) %3
    wire [1:0] mid_idx = (wr_idx == 2'd0) ? 2'd2 : wr_idx - 2'd1;   // (wr-1) %3
    wire [1:0] bot_idx = wr_idx;

    // ----- Write current pixel into bot buffer -----
    always @(posedge clk) begin
        if (pix_valid)
            lb[wr_idx][h_count] <= pix_in;
    end

    // ----- Advance wr_idx at end-of-line -----
    always @(posedge clk) begin
        if (rst)
            wr_idx <= 2'd0;
        else if (pix_valid && h_count == WIDTH - 1)
            wr_idx <= (wr_idx == 2'd2) ? 2'd0 : wr_idx + 2'd1;
    end

    // ----- Window column indices (window spans h-2, h-1, h) -----
    wire [9:0] col_l = (h_count >= 10'd2) ? h_count - 10'd2 : 10'd0;
    wire [9:0] col_c = (h_count >= 10'd1) ? h_count - 10'd1 : 10'd0;
    wire [9:0] col_r = h_count;

    // ----- Registered window outputs -----
    // top, mid: read from completed buffers (no hazard).
    // bot:      read cols h-2 and h-1 normally; forward pix_in into bot_r.
    always @(posedge clk) begin
        top_l <= lb[top_idx][col_l];
        top_c <= lb[top_idx][col_c];
        top_r <= lb[top_idx][col_r];
        mid_l <= lb[mid_idx][col_l];
        mid_c <= lb[mid_idx][col_c];
        mid_r <= lb[mid_idx][col_r];
        bot_l <= lb[bot_idx][col_l];
        bot_c <= lb[bot_idx][col_c];
        bot_r <= pix_in;                  // col_r == h_count, forward to avoid hazard
    end

endmodule
