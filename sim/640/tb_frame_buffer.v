`timescale 1ns/1ps
// Verifies frame_buffer:
//   - luma write/read at distinct addresses
//   - chroma is 4:2:2 subsampled: chroma_addr = wr_addr[18:1]
//     so adjacent even/odd pixel pair share one chroma word
//   - wr_chroma_en gates chroma write only
module tb_frame_buffer;
    reg clk = 0;
    always #5 clk = ~clk;

    reg         wr_en        = 0;
    reg  [18:0] wr_addr      = 0;
    reg  [2:0]  wr_luma      = 0;
    reg  [3:0]  wr_chroma    = 0;
    reg         wr_chroma_en = 0;
    reg  [18:0] rd_addr      = 0;
    wire [2:0]  rd_luma;
    wire [3:0]  rd_chroma;

    frame_buffer dut (
        .wr_clk(clk), .wr_en(wr_en),
        .wr_addr(wr_addr), .wr_luma(wr_luma),
        .wr_chroma(wr_chroma), .wr_chroma_en(wr_chroma_en),
        .rd_clk(clk), .rd_addr(rd_addr),
        .rd_luma(rd_luma), .rd_chroma(rd_chroma)
    );

    integer errors = 0;

    task write_pixel;
        input [18:0] a;
        input [2:0]  y;
        input [3:0]  c;
        input        cen;
        begin
            @(negedge clk);
            wr_addr      = a;
            wr_luma      = y;
            wr_chroma    = c;
            wr_chroma_en = cen;
            wr_en        = 1'b1;
            @(posedge clk);
            @(negedge clk);
            wr_en = 1'b0;
        end
    endtask

    task check_read;
        input [18:0] a;
        input [2:0]  exp_y;
        input [3:0]  exp_c;
        begin
            @(negedge clk);
            rd_addr = a;
            @(posedge clk);   // BRAM 1-cycle latency
            @(negedge clk);
            if (rd_luma !== exp_y) begin
                $display("FAIL: addr=%0d luma got=%0d exp=%0d", a, rd_luma, exp_y);
                errors = errors + 1;
            end
            if (rd_chroma !== exp_c) begin
                $display("FAIL: addr=%0d chroma got=%0h exp=%0h", a, rd_chroma, exp_c);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/640/frame_buffer.vcd");
        $dumpvars(0, tb_frame_buffer);

        // Pixel 0 (even): write luma=1 chroma=4'hA, chroma_en=1
        write_pixel(19'd0, 3'd1, 4'hA, 1'b1);
        // Pixel 1 (odd):  write luma=2 chroma=4'h0, chroma_en=0
        //   chroma word at addr[18:1]=0 must remain 4'hA (shared with pixel 0)
        write_pixel(19'd1, 3'd2, 4'h0, 1'b0);
        // Pixel 2 (even): write luma=3 chroma=4'h5, chroma_en=1
        write_pixel(19'd2, 3'd3, 4'h5, 1'b1);
        // Pixel 3 (odd):  write luma=4 chroma=4'h0, chroma_en=0 (shares pixel 2's 4'h5)
        write_pixel(19'd3, 3'd4, 4'h0, 1'b0);
        // Distant pixel
        write_pixel(19'd1000, 3'd7, 4'hF, 1'b1);

        // Read back
        check_read(19'd0,    3'd1, 4'hA);   // pair 0
        check_read(19'd1,    3'd2, 4'hA);   // shares pair 0 chroma
        check_read(19'd2,    3'd3, 4'h5);   // pair 1
        check_read(19'd3,    3'd4, 4'h5);   // shares pair 1 chroma
        check_read(19'd1000, 3'd7, 4'hF);

        if (errors == 0) $display("PASS: frame_buffer luma + 4:2:2 chroma sharing OK");
        else begin
            $display("FAIL: %0d errors", errors);
            $finish_and_return(1);
        end
        $finish;
    end
endmodule
