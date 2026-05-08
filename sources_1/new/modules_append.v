
// === line_buffer3 module - appended for synthesis ===
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

// === filter_edge module - appended for synthesis ===
module filter_edge (
    input  wire [2:0]  top_l, top_c, top_r,
    input  wire [2:0]  mid_l, mid_c, mid_r,
    input  wire [2:0]  bot_l, bot_c, bot_r,
    input  wire [3:0]  threshold,
    input  wire        h_edge,
    input  wire        v_edge,
    output wire [11:0] out_rgb444
);

    wire [2:0] y00 = top_l;
    wire [2:0] y01 = top_c;
    wire [2:0] y02 = top_r;
    wire [2:0] y10 = mid_l;
    wire [2:0] y12 = mid_r;
    wire [2:0] y20 = bot_l;
    wire [2:0] y21 = bot_c;
    wire [2:0] y22 = bot_r;

    wire signed [5:0] right_col = $signed({3'b0, y02}) + $signed({2'b0, y12, 1'b0}) + $signed({3'b0, y22});
    wire signed [5:0] left_col  = $signed({3'b0, y00}) + $signed({2'b0, y10, 1'b0}) + $signed({3'b0, y20});
    wire signed [5:0] bot_row   = $signed({3'b0, y20}) + $signed({2'b0, y21, 1'b0}) + $signed({3'b0, y22});
    wire signed [5:0] top_row   = $signed({3'b0, y00}) + $signed({2'b0, y01, 1'b0}) + $signed({3'b0, y02});

    wire signed [5:0] Gx = right_col - left_col;
    wire signed [5:0] Gy = bot_row   - top_row;

    wire [5:0] abs_Gx = Gx[5] ? (~Gx + 6'd1) : Gx;
    wire [5:0] abs_Gy = Gy[5] ? (~Gy + 6'd1) : Gy;

    wire [6:0] mag = {1'b0, abs_Gx} + {1'b0, abs_Gy};
    wire [6:0] thresh_scaled = {3'b000, threshold};

    assign out_rgb444 = (h_edge || v_edge) ? 12'h000
                      : (mag > thresh_scaled)  ? 12'hFFF
                      :                          12'h000;

endmodule
