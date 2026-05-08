module camera_capture_640x320(
    input pclk, vsync, href,
    input [7:0] d_in,
    output reg [16:0] addr_out,
    output reg [11:0] data_out,
    output reg write_en
);
    reg [7:0] b1;
    reg byte_sel = 0;
    reg [9:0] line_cnt = 0;
    reg [9:0] pxl_cnt = 0;
    reg old_href = 0;

    always @(posedge pclk) begin
        old_href <= href;

        if (vsync) begin
            addr_out <= 0;
            line_cnt <= 0;
            pxl_cnt <= 0;
            byte_sel <= 0;
            write_en <= 0;
        end else if (href) begin
            if (byte_sel == 0) begin
                b1 <= d_in;
                byte_sel <= 1;
                write_en <= 0;
            end else begin
                // Downsample: เก็บเฉพาะบรรทัดคู่และพิกเซลคู่ (ย่อ 640x480 -> 320x240)
                if (line_cnt[0] == 0 && pxl_cnt[0] == 0 && addr_out < 76800) begin
                    data_out <= {b1[7:4], b1[2:0],d_in[7],d_in[4:1]};
                    write_en <= 1;
                    addr_out <= addr_out + 1;
                end else begin
                    write_en <= 0;
                end
                pxl_cnt <= pxl_cnt + 1;
                byte_sel <= 0;
            end
        end else begin
            write_en <= 0;
            pxl_cnt <= 0; // รีเซ็ตตัวนับพิกเซลแนวนอนเมื่อจบบรรทัด
            byte_sel <= 0; // [CRITICAL FIX] รีเซ็ต byte_sel เพื่อป้องกันสีเพี้ยน
            // (High/Low byte สลับกัน)
            if (old_href == 1 && href == 0) begin
                line_cnt <= line_cnt + 1; // ขยับบรรทัดถัดไป
            end
        end
    end
endmodule
