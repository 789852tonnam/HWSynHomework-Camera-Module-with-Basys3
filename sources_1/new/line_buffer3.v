`timescale 1ns/1ps
// line_buffer3.v
// 3-line circular shift buffer for 3×3 Sobel neighbourhood.
// Simplified for synthesis.

module line_buffer3 #(
    parameter WIDTH = 640
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

    (* ram_style = "distributed" *)
    reg [2:0] lb [0:2][0:WIDTH-1];
    integer _ii, _jj;
    initial begin
        for (_ii = 0; _ii < 3; _ii = _ii + 1)
            for (_jj = 0; _jj < WIDTH; _jj = _jj + 1)
                lb[_ii][_jj] = 3'b0;
    end

    // wr_idx = buffer being written this row = bot (row N, newest).
    // top = (wr+1)%3 = row N-2 (oldest complete).
    // mid = (wr-1)%3 = row N-1 (most recent complete).
    // bot = wr_idx   = row N   (currently being written).
    reg [1:0] wr_idx;
    wire [1:0] top_idx = (wr_idx == 2'd2) ? 2'd0 : wr_idx + 2'd1;
    wire [1:0] mid_idx = (wr_idx == 2'd0) ? 2'd2 : wr_idx - 2'd1;
    wire [1:0] bot_idx = wr_idx;

    always @(posedge clk) begin
        if (pix_valid)
            lb[wr_idx][h_count] <= pix_in;
    end

    always @(posedge clk) begin
        if (rst)
            wr_idx <= 2'd0;
        else if (pix_valid && h_count == WIDTH - 1)
            wr_idx <= (wr_idx == 2'd2) ? 2'd0 : wr_idx + 2'd1;
    end

    // Window spans columns (h-2, h-1, h).  col_r == h_count.
    // bot_r forwarded from pix_in to avoid read-before-write hazard on
    // the current row (lb[bot_idx][h_count] not yet committed this cycle).
    wire [9:0] col_l = (h_count >= 10'd2) ? h_count - 10'd2 : 10'd0;
    wire [9:0] col_c = (h_count >= 10'd1) ? h_count - 10'd1 : 10'd0;

    always @(posedge clk) begin
        top_l <= lb[top_idx][col_l];
        top_c <= lb[top_idx][col_c];
        top_r <= lb[top_idx][h_count];
        mid_l <= lb[mid_idx][col_l];
        mid_c <= lb[mid_idx][col_c];
        mid_r <= lb[mid_idx][h_count];
        bot_l <= lb[bot_idx][col_l];
        bot_c <= lb[bot_idx][col_c];
        bot_r <= pix_in;           // forward: col_r == h_count, avoids hazard
    end

endmodule
