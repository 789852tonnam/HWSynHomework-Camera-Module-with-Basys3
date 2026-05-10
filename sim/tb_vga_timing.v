`timescale 1ns/1ps
// Verifies VGA 640x480@60 timing generator:
//   - h_count wraps 0..799, v_count wraps 0..520
//   - hsync active-LOW in h=[656..751]
//   - vsync active-LOW in v=[490..491]
//   - active_video high iff h<640 && v<480
//   - rd_addr non-zero only inside active region
module tb_vga_timing;
    reg         clk = 0;
    reg         rst = 1;
    wire [9:0]  h_count, v_count;
    wire        hsync, vsync, active_video;
    wire [18:0] rd_addr;

    always #20 clk = ~clk;   // 25 MHz pixel clock (40 ns period)

    vga_timing dut (
        .clk(clk), .rst(rst),
        .h_count(h_count), .v_count(v_count),
        .hsync(hsync), .vsync(vsync),
        .active_video(active_video), .rd_addr(rd_addr)
    );

    integer errors = 0;
    integer max_h = 0, max_v = 0;

    // Continuously check sync polarity + active region matches counters
    always @(posedge clk) if (!rst) begin
        if (h_count > max_h) max_h = h_count;
        if (v_count > max_v) max_v = v_count;

        // hsync expected polarity
        if ((h_count >= 656 && h_count < 752) && hsync !== 1'b0) begin
            $display("FAIL @t=%0t: hsync should be 0 at h=%0d", $time, h_count);
            errors = errors + 1;
        end
        if ((h_count < 656 || h_count >= 752) && hsync !== 1'b1) begin
            $display("FAIL @t=%0t: hsync should be 1 at h=%0d", $time, h_count);
            errors = errors + 1;
        end

        // vsync expected polarity
        if ((v_count >= 490 && v_count < 492) && vsync !== 1'b0) begin
            $display("FAIL @t=%0t: vsync should be 0 at v=%0d", $time, v_count);
            errors = errors + 1;
        end
        if ((v_count < 490 || v_count >= 492) && vsync !== 1'b1) begin
            $display("FAIL @t=%0t: vsync should be 1 at v=%0d", $time, v_count);
            errors = errors + 1;
        end

        // active_video expected
        if ((h_count < 640) && (v_count < 480)) begin
            if (active_video !== 1'b1) begin
                $display("FAIL @t=%0t: active_video=0 inside (h=%0d,v=%0d)", $time, h_count, v_count);
                errors = errors + 1;
            end
        end else begin
            if (active_video !== 1'b0) begin
                $display("FAIL @t=%0t: active_video=1 outside (h=%0d,v=%0d)", $time, h_count, v_count);
                errors = errors + 1;
            end
            if (rd_addr !== 19'd0) begin
                $display("FAIL @t=%0t: rd_addr=%0h non-zero in blanking", $time, rd_addr);
                errors = errors + 1;
            end
        end
    end

    initial begin
        $dumpfile("sim/vga_timing.vcd");
        $dumpvars(0, tb_vga_timing);

        repeat (4) @(posedge clk);
        rst = 0;

        // Run > 1 full frame: 800 * 521 = 416800 cycles
        repeat (430000) @(posedge clk);

        if (max_h !== 799) begin
            $display("FAIL: max h_count=%0d expected 799", max_h);
            errors = errors + 1;
        end
        if (max_v !== 520) begin
            $display("FAIL: max v_count=%0d expected 520", max_v);
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS: VGA timing OK (max_h=%0d max_v=%0d)", max_h, max_v);
        else begin
            $display("FAIL: %0d errors", errors);
            $finish_and_return(1);
        end
        $finish;
    end
endmodule
