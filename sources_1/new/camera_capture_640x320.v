`timescale 1ns/1ps
module camera_capture_640x320(
    input pclk, vsync, href,
    input [7:0] d_in,
    output reg [16:0] addr_out,
    output reg [11:0] data_out,
    output reg write_en
);
    // Skip first PIXEL_SKIP camera pixels per line (OV7670 HREF startup garbage).
    // Must be even. Each unit = 1 camera pixel (2 bytes). Tune if black bar persists.
    localparam [9:0] PIXEL_SKIP = 10'd20;

    reg [7:0]  b1;
    reg        byte_sel = 0;
    reg [9:0]  line_cnt = 0;
    reg [9:0]  pxl_cnt  = 0;
    reg        old_href  = 0;
    reg [16:0] row_base  = 0;  // base address of current fb row (0, 320, 640, ...)
    reg [9:0]  write_col = 0;  // column index within current fb row

    always @(posedge pclk) begin
        old_href <= href;

        if (vsync) begin
            addr_out  <= 0;
            line_cnt  <= 0;
            pxl_cnt   <= 0;
            byte_sel  <= 0;
            write_en  <= 0;
            row_base  <= 0;
            write_col <= 0;
        end else if (href) begin
            if (byte_sel == 0) begin
                b1       <= d_in;
                byte_sel <= 1;
                write_en <= 0;
            end else begin
                // Even camera lines, even pixel >= PIXEL_SKIP, within fb row width
                if (line_cnt[0] == 0 && pxl_cnt[0] == 0 &&
                    pxl_cnt >= PIXEL_SKIP && write_col < 320) begin
                    data_out  <= {b1[7:4], b1[2:0], d_in[7], d_in[4:1]};
                    addr_out  <= row_base + {7'd0, write_col};
                    write_en  <= 1;
                    write_col <= write_col + 1;
                end else begin
                    write_en <= 0;
                end
                pxl_cnt  <= pxl_cnt + 1;
                byte_sel <= 0;
            end
        end else begin
            write_en  <= 0;
            pxl_cnt   <= 0;
            write_col <= 0;
            byte_sel  <= 0;
            if (old_href == 1 && href == 0) begin
                line_cnt <= line_cnt + 1;
                // Advance row_base after each even camera line
                if (line_cnt[0] == 0)
                    row_base <= row_base + 17'd320;
            end
        end
    end
endmodule
