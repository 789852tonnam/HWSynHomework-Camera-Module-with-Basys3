`timescale 1ns / 1ps
module edge_unit(
    input clk,
    input [3:0] raw_r,
    input [3:0] raw_g,
    input [3:0] raw_b,
    input video_active,
    output reg [3:0] edge_out
);
    reg [3:0] prev_gray = 4'h0;
    reg edge_valid = 1'b0;

    wire [7:0] R_ext = {raw_r, 4'b0000};
    wire [7:0] G_ext = {raw_g, 4'b0000};
    wire [7:0] B_ext = {raw_b, 4'b0000};
    wire [7:0] Y_calc = (R_ext >> 2) + (R_ext >> 4) + (G_ext >> 1) + (G_ext >> 4) + (B_ext >> 3);
    wire [3:0] gray_val = Y_calc[7:4];

    always @(posedge clk) begin
        if (!video_active) begin
            prev_gray <= 4'h0;
            edge_valid <= 1'b0;
        end else begin
            prev_gray <= gray_val;
            edge_valid <= 1'b1;
        end
    end

    wire [3:0] edge_diff = (gray_val > prev_gray) ? (gray_val - prev_gray) : (prev_gray - gray_val);

    always @(*) begin
        edge_out = (edge_valid && (edge_diff > 4'h2)) ? 4'hF : 4'h0;
    end

endmodule
