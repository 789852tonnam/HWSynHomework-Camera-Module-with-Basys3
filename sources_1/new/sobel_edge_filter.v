module sobel_edge_filter(
    input clk,
    input reset,
    input active,
    input [9:0] pixel_x,
    input [9:0] pixel_y,
    input [11:0] pixel_in,
    output reg [3:0] edge_out
);
    localparam WIDTH = 640;

    reg [3:0] line0 [0:WIDTH-1];
    reg [3:0] line1 [0:WIDTH-1];
    reg [3:0] line2 [0:WIDTH-1];
    reg [1:0] phase = 2'd0;

    reg [3:0] cur_l1 = 4'h0;
    reg [3:0] cur_l2 = 4'h0;

    wire [7:0] r_ext = {pixel_in[11:8], 4'b0000};
    wire [7:0] g_ext = {pixel_in[7:4], 4'b0000};
    wire [7:0] b_ext = {pixel_in[3:0], 4'b0000};
    wire [7:0] y_calc = (r_ext >> 2) + (r_ext >> 4) + (g_ext >> 1) + (g_ext >> 4) + (b_ext >> 3);
    wire [3:0] gray = y_calc[7:4];

    function [3:0] read_line;
        input [1:0] sel;
        input [9:0] idx;
        begin
            case (sel)
                2'd0: read_line = line0[idx];
                2'd1: read_line = line1[idx];
                default: read_line = line2[idx];
            endcase
        end
    endfunction

    wire [1:0] top_sel = phase;
    wire [1:0] mid_sel = (phase == 2'd2) ? 2'd0 : phase + 2'd1;
    wire [1:0] cur_sel = (phase == 2'd0) ? 2'd2 : phase - 2'd1;

    wire [3:0] top0 = read_line(top_sel, pixel_x - 10'd2);
    wire [3:0] top1 = read_line(top_sel, pixel_x - 10'd1);
    wire [3:0] top2 = read_line(top_sel, pixel_x);
    wire [3:0] mid0 = read_line(mid_sel, pixel_x - 10'd2);
    wire [3:0] mid1 = read_line(mid_sel, pixel_x - 10'd1);
    wire [3:0] mid2 = read_line(mid_sel, pixel_x);

    wire signed [6:0] gx = $signed({3'b0, top2}) + ($signed({3'b0, mid2}) <<< 1) + $signed({3'b0, mid2})
                          - $signed({3'b0, top0}) - ($signed({3'b0, mid0}) <<< 1) - $signed({3'b0, mid0});
    wire signed [6:0] gy = $signed({3'b0, top0}) + ($signed({3'b0, top1}) <<< 1) + $signed({3'b0, top2})
                          - $signed({3'b0, mid0}) - ($signed({3'b0, mid1}) <<< 1) - $signed({3'b0, mid2});

    wire [7:0] abs_gx = gx[6] ? (~gx[6:0] + 1'b1) : gx[6:0];
    wire [7:0] abs_gy = gy[6] ? (~gy[6:0] + 1'b1) : gy[6:0];
    wire [8:0] mag = abs_gx + abs_gy;

    always @(*) begin
        if (active && pixel_x >= 10'd2 && pixel_y >= 10'd2 && mag > 9'd20) begin
            edge_out = 4'hF;
        end else begin
            edge_out = 4'h0;
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            phase <= 2'd0;
            cur_l1 <= 4'h0;
            cur_l2 <= 4'h0;
        end else if (active) begin
            if (pixel_x == 10'd0) begin
                cur_l1 <= 4'h0;
                cur_l2 <= 4'h0;
                if (pixel_y != 10'd0) begin
                    phase <= (phase == 2'd2) ? 2'd0 : phase + 2'd1;
                end
            end else begin
                cur_l2 <= cur_l1;
                cur_l1 <= gray;
            end

            case (cur_sel)
                2'd0: line0[pixel_x] <= gray;
                2'd1: line1[pixel_x] <= gray;
                default: line2[pixel_x] <= gray;
            endcase
        end
    end
endmodule
