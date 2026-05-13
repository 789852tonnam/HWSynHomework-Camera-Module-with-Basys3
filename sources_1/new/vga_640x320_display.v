`timescale 1ns/1ps
module vga_640x320_display(
    input clk_25m,
    input [11:0] pixel_in,
    output hsync,
    output vsync,
    output [3:0] vga_r,
    output [3:0] vga_g,
    output [3:0] vga_b,
    output [16:0] frame_addr,
    output active,
    output [9:0] pixel_x,
    output [9:0] pixel_y
);
    reg [9:0] h_cnt = 0, v_cnt = 0;
    reg active_d = 0;
    reg [9:0] pixel_x_d = 0;
    reg [9:0] pixel_y_d = 0;

    always @(posedge clk_25m) begin
        if (h_cnt == 799) begin
            h_cnt <= 0;
            v_cnt <= (v_cnt == 524) ? 0 : v_cnt + 1;
        end else begin
            h_cnt <= h_cnt + 1;
        end

        active_d  <= (h_cnt < 640 && v_cnt < 480);
        pixel_x_d <= h_cnt;
        pixel_y_d <= v_cnt;
    end

    assign hsync = (h_cnt >= 656 && h_cnt < 752) ? 0 : 1;
    assign vsync = (v_cnt >= 490 && v_cnt < 492) ? 0 : 1;

    wire display_area = (h_cnt < 640 && v_cnt < 480);
    // (h_cnt*496)>>10 maps h_cnt=0..639 to img_x=0..309 (PIXEL_SKIP=20 -> 310 valid fb cols)
    wire [19:0] scaled_x = (h_cnt * 496) >> 10;
    wire [9:0]  img_x    = scaled_x[9:0];
    wire [9:0]  img_y    = v_cnt >> 1;

    assign frame_addr = display_area ? (img_y * 320 + img_x) : 0;
    assign active     = active_d;
    assign pixel_x    = pixel_x_d;
    assign pixel_y    = pixel_y_d;

    assign vga_r = active_d ? pixel_in[11:8] : 4'h0;
    assign vga_g = active_d ? pixel_in[7:4]  : 4'h0;
    assign vga_b = active_d ? pixel_in[3:0]  : 4'h0;
endmodule
