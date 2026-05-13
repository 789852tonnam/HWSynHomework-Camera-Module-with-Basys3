`timescale 1ns / 1ps

module top_module(
    input clk_100mhz,
    input reset,
    input [3:0] sw,      // sw[1:0] for Mode, sw[3:2] for Color Isolation Selection
    output ov7670_xclk,
    input ov7670_pclk,
    input ov7670_vsync,
    input ov7670_href,
    input [7:0] ov7670_data,
    output ov7670_sioc,
    inout ov7670_siod,
    output ov7670_pwdn,
    output ov7670_rst,
    // VGA Pins
    output [3:0] vga_r, vga_g, vga_b,
    output vga_hsync, vga_vsync
);
    // --- State Definition ---
    parameter S_NORMAL   = 2'b00;
    parameter S_EDGE     = 2'b01;
    parameter S_INVERSION = 2'b10;
    parameter S_CISOLATION = 2'b11;

    reg [1:0] current_state = S_NORMAL;

    // --- Signals ---
    wire clk_25m, clk_24m;
    wire [16:0] frame_addr;
    wire [11:0] pixel_12bit;
    wire [16:0] capture_addr; // [FIXED] ขนาดต้องเป็น 17-bit ให้ตรงกับ capture module
    wire [11:0] capture_data;
    wire capture_we;

    // สัญญาณสีที่จะส่งออก VGA จริงๆ
    reg [3:0] r_out, g_out, b_out;

    // --- Module Instantiations ---
    clk_wiz_0 clock_gen (.clk_in1(clk_100mhz), .clk_out1(clk_25m), .clk_out2(clk_24m));
    assign ov7670_xclk = clk_24m;
    assign ov7670_pwdn = 1'b0;
    assign ov7670_rst  = 1'b1;

    sccb_config config_inst (.clk(clk_25m), .sioc(ov7670_sioc), .siod(ov7670_siod));

    camera_capture_640x320 capture_inst (
        .pclk(ov7670_pclk), .vsync(ov7670_vsync), .href(ov7670_href),
        .d_in(ov7670_data), .addr_out(capture_addr), .data_out(capture_data), .write_en(capture_we)
    );

    frame_buffer_640x320 ram_inst (
        .clk_w(ov7670_pclk), .we(capture_we), .addr_w(capture_addr), .din(capture_data),
        .clk_r(clk_25m), .addr_r(frame_addr),
        .dout(pixel_12bit) // [FIXED] แก้จาก pixel_8bit เป็น pixel_12bit
    );


    wire [3:0] raw_r, raw_g, raw_b;
    wire video_active;
    wire [9:0] video_x;
    wire [9:0] video_y;
    vga_640x320_display vga_inst (
        .clk_25m(clk_25m), .pixel_in(pixel_12bit),
        .hsync(vga_hsync), .vsync(vga_vsync),
        .vga_r(raw_r), .vga_g(raw_g), .vga_b(raw_b),
        .frame_addr(frame_addr),
        .active(video_active),
        .pixel_x(video_x),
        .pixel_y(video_y)
    );

    // --- Edge detection using rtl/line_buffer3 + rtl/filter_edge ---
    // Convert 12-bit pixel to 4-bit gray then 3-bit luma for the rtl filter
    wire [3:0] gray4;
    wire [2:0] gray3;
    // simple luma approximation: use existing 4-bit gray (Y_calc[7:4]) if available
    // derive from pixel_12bit: R[11:8], G[7:4], B[3:0]
    assign gray4 = (pixel_12bit[11:8] + pixel_12bit[7:4] + pixel_12bit[3:0]) / 3;
    assign gray3 = gray4[3:1]; // reduce to 3 bits for rtl filter

    // Instantiate 3-line buffer (from rtl/line_buffer3.v)
    wire [2:0] top_l, top_c, top_r;
    wire [2:0] mid_l, mid_c, mid_r;
    wire [2:0] bot_l, bot_c, bot_r;

    line_buffer3 #(.WIDTH(640)) lb3_inst (
        .clk(clk_25m), .rst(reset),
        .pix_in(gray3), .pix_valid(video_active),
        .h_count(video_x), .v_count(video_y),
        .top_l(top_l), .top_c(top_c), .top_r(top_r),
        .mid_l(mid_l), .mid_c(mid_c), .mid_r(mid_r),
        .bot_l(bot_l), .bot_c(bot_c), .bot_r(bot_r)
    );

    // threshold from switches (use sw[3:0])
    wire [3:0] edge_thresh = sw[3:0];
    wire h_edge = (video_x == 10'd0) || (video_x == 10'd639);
    wire v_edge = (video_y < 10'd2) || (video_y >= 10'd479);

    wire [11:0] edge_rgb444;
    filter_edge edge_inst (
        .top_l(top_l), .top_c(top_c), .top_r(top_r),
        .mid_l(mid_l), .mid_c(mid_c), .mid_r(mid_r),
        .bot_l(bot_l), .bot_c(bot_c), .bot_r(bot_r),
        .threshold(edge_thresh),
        .h_edge(h_edge), .v_edge(v_edge),
        .out_rgb444(edge_rgb444)
    );

    // Map edge_rgb444 (12-bit) to 4-bit channels
    wire [3:0] edge_r = edge_rgb444[11:8];
    wire [3:0] edge_g = edge_rgb444[7:4];
    wire [3:0] edge_b = edge_rgb444[3:0];

    // --- State Machine Logic ---
    always @(posedge clk_25m) begin
        if (reset) begin
            current_state <= S_NORMAL;
        end else begin
            case (sw[1:0])
                2'b00: current_state <= S_NORMAL;
                2'b01: current_state <= S_EDGE;
                2'b10: current_state <= S_INVERSION;
                2'b11: current_state <= S_CISOLATION; // [FIXED] แก้ typo จาก <+ เป็น <=
                default: current_state <= S_NORMAL;
            endcase
        end
    end

    always @(*) begin
        case (current_state)
            S_NORMAL: begin
                r_out = raw_r;
                g_out = raw_g;
                b_out = raw_b;
            end
            S_EDGE: begin
                r_out = edge_r;
                g_out = edge_g;
                b_out = edge_b;
            end
            S_INVERSION: begin
                r_out = ~raw_r;
                g_out = ~raw_g;
                b_out = ~raw_b;
            end
            S_CISOLATION: begin
                // Use sw[3:2] to select isolation channel:
                // 00: Red Only, 01: Green Only, 10: Blue Only, 11: All (Normal-ish)
                case (sw[3:2])
                    2'b00: begin r_out = raw_r; g_out = 4'h0; b_out = 4'h0; end // Red Only
                    2'b01: begin r_out = 4'h0; g_out = raw_g; b_out = 4'h0; end // Green Only
                    2'b10: begin r_out = 4'h0; g_out = 4'h0; b_out = raw_b; end // Blue Only
                    2'b11: begin r_out = raw_r; g_out = raw_g; b_out = raw_b; end // All
                    default: begin r_out = raw_r; g_out = 4'h0; b_out = 4'h0; end
                endcase
            end
            default: begin
                r_out = raw_r;
                g_out = raw_g;
                b_out = raw_b;
            end
        endcase
    end
    assign vga_r = video_active ? r_out : 4'h0;
    assign vga_g = video_active ? g_out : 4'h0;
    assign vga_b = video_active ? b_out : 4'h0;

endmodule
