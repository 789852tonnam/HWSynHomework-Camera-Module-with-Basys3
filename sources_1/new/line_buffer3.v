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

    reg [1:0] wr_idx;
    wire [1:0] rd_bot_idx = (wr_idx == 2'd0) ? 2'd2 : (wr_idx == 2'd1) ? 2'd0 : 2'd1;
    wire [1:0] rd_mid_idx = (wr_idx == 2'd0) ? 2'd1 : (wr_idx == 2'd1) ? 2'd2 : 2'd0;
    wire [1:0] rd_top_idx = wr_idx;

    always @(posedge clk) begin
        if (pix_valid) begin
            lb[wr_idx][h_count] <= pix_in;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            wr_idx <= 2'd0;
        end else if (pix_valid && h_count == WIDTH - 1) begin
            wr_idx <= (wr_idx == 2'd2) ? 2'd0 : wr_idx + 2'd1;
        end
    end

    wire [9:0] col_l = (h_count > 0) ? h_count - 10'd1 : 10'd0;
    wire [9:0] col_c = h_count;
    wire [9:0] col_r = (h_count < WIDTH - 1) ? h_count + 10'd1 : (WIDTH - 1);

    always @(posedge clk) begin
        top_l <= lb[rd_top_idx][col_l];
        top_c <= lb[rd_top_idx][col_c];
        top_r <= lb[rd_top_idx][col_r];
        mid_l <= lb[rd_mid_idx][col_l];
        mid_c <= lb[rd_mid_idx][col_c];
        mid_r <= lb[rd_mid_idx][col_r];
        bot_l <= lb[rd_bot_idx][col_l];
        bot_c <= lb[rd_bot_idx][col_c];
        bot_r <= lb[rd_bot_idx][col_r];
    end

endmodule
