`timescale 1ns/1ps
// Verifies frame_buffer_640x320 (320-path RGB444 BRAM):
//   - 76,800 entries x 12 bits (one 12-bit RGB444 per pixel)
//   - Dual-clock: write @ clk_w, read @ clk_r (same clock used here)
//   - 1-cycle synchronous read latency
//   - we gate: no write when we=0
module tb_frame_buffer_640x320;
    reg         clk  = 0;
    reg         we   = 0;
    reg  [16:0] addr_w = 0;
    reg  [11:0] din    = 0;
    reg  [16:0] addr_r = 0;
    wire [11:0] dout;

    always #5 clk = ~clk;   // 100 MHz (both ports same clock)

    frame_buffer_640x320 dut (
        .clk_w(clk), .we(we), .addr_w(addr_w), .din(din),
        .clk_r(clk), .addr_r(addr_r), .dout(dout)
    );

    integer errors = 0;

    task write_px;
        input [16:0] a;
        input [11:0] d;
        begin
            @(negedge clk);
            addr_w = a; din = d; we = 1'b1;
            @(posedge clk);
            @(negedge clk);
            we = 1'b0;
        end
    endtask

    task check_px;
        input [16:0] a;
        input [11:0] exp;
        begin
            @(negedge clk);
            addr_r = a;
            @(posedge clk);      // BRAM 1-cycle latency
            @(negedge clk);
            if (dout !== exp) begin
                $display("FAIL: addr=%0d got=%h exp=%h", a, dout, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/320/frame_buffer_320.vcd");
        $dumpvars(0, tb_frame_buffer_640x320);

        // Write several addresses
        write_px(17'd0,     12'hABC);
        write_px(17'd1,     12'h123);
        write_px(17'd319,   12'hFFF);   // last pixel of row 0
        write_px(17'd320,   12'hDEF);   // first pixel of row 1
        write_px(17'd76799, 12'h555);   // last pixel in buffer

        // Read back and verify
        check_px(17'd0,     12'hABC);
        check_px(17'd1,     12'h123);
        check_px(17'd319,   12'hFFF);
        check_px(17'd320,   12'hDEF);
        check_px(17'd76799, 12'h555);

        // Verify we=0 does not overwrite
        @(negedge clk); addr_w = 0; din = 12'hXXX; we = 1'b0;
        @(posedge clk);
        check_px(17'd0, 12'hABC);   // must still be ABC

        if (errors == 0) $display("PASS: frame_buffer_640x320 R/W + we-gate OK");
        else begin
            $display("FAIL: %0d errors", errors);
            $finish_and_return(1);
        end
        $finish;
    end
endmodule
