`timescale 1ns/1ps
// Verifies filter_pipeline 4-mode mux (RAW/INVERT/COLOR_ISO/EDGE).
//
// Drives a constant gray luma+neutral chroma with pix_valid high so the
// 2-cycle output pipeline settles, then samples rgb444_out for each mode:
//   - RAW    : non-zero RGB (mid gray)
//   - INVERT : ~raw
//   - ISO_R  : only R nibble non-zero, G/B == 0
//   - ISO_G  : only G nibble non-zero
//   - ISO_B  : only B nibble non-zero
//   - EDGE   : flat field -> mag=0 -> 12'h000
module tb_filter_pipeline;
    reg clk = 0;
    always #5 clk = ~clk;

    reg         rst       = 1;
    reg  [2:0]  fb_luma   = 3'd0;
    reg  [3:0]  fb_chroma = 4'b0000;
    reg  [9:0]  h_count   = 10'd100;
    reg  [9:0]  v_count   = 10'd100;
    reg         pix_valid = 1'b1;
    reg  [1:0]  sw_mode   = 2'b00;
    reg  [1:0]  sw32      = 2'b00;
    reg  [3:0]  sw74      = 4'd1;
    reg         h_edge    = 1'b0;
    reg         v_edge    = 1'b0;
    wire [11:0] rgb444_out;

    filter_pipeline #(.WIDTH(640)) dut (
        .clk(clk), .rst(rst),
        .fb_luma(fb_luma), .fb_chroma(fb_chroma),
        .h_count(h_count), .v_count(v_count), .pix_valid(pix_valid),
        .sw_mode(sw_mode), .sw32(sw32), .sw74(sw74),
        .h_edge(h_edge), .v_edge(v_edge),
        .rgb444_out(rgb444_out)
    );

    integer errors = 0;

    task settle;
        begin
            // Pipeline depth is 2 cycles after sw_mode change
            repeat (4) @(posedge clk);
        end
    endtask

    reg [11:0] raw_sample;

    initial begin
        $dumpfile("sim/filter_pipeline.vcd");
        $dumpvars(0, tb_filter_pipeline);

        repeat (4) @(posedge clk);
        rst = 0;
        @(negedge clk);
        // Drive luma + chroma to test values (forces always @(*) to re-evaluate)
        fb_luma   = 3'd4;            // mid-gray
        fb_chroma = 4'b1010;         // cb=2, cr=2 (mild + bins)

        // ----- RAW -----
        sw_mode = 2'b00;
        settle;
        raw_sample = rgb444_out;
        if (raw_sample === 12'h000) begin
            $display("FAIL: RAW out=000, expected non-zero gray");
            errors = errors + 1;
        end

        // ----- INVERT -----
        sw_mode = 2'b01;
        settle;
        if (rgb444_out !== ~raw_sample) begin
            $display("FAIL: INVERT got=%h exp=%h", rgb444_out, ~raw_sample);
            errors = errors + 1;
        end

        // ----- COLOR_ISO R -----
        sw_mode = 2'b10;
        sw32    = 2'b00;
        settle;
        if (rgb444_out[7:0] !== 8'h00) begin
            $display("FAIL: ISO_R G/B not zero, got=%h", rgb444_out);
            errors = errors + 1;
        end
        if (rgb444_out[11:8] === 4'h0) begin
            $display("FAIL: ISO_R R-nibble zero, got=%h", rgb444_out);
            errors = errors + 1;
        end

        // ----- COLOR_ISO G -----
        sw32 = 2'b01;
        settle;
        if (rgb444_out[11:8] !== 4'h0 || rgb444_out[3:0] !== 4'h0) begin
            $display("FAIL: ISO_G R/B not zero, got=%h", rgb444_out);
            errors = errors + 1;
        end
        if (rgb444_out[7:4] === 4'h0) begin
            $display("FAIL: ISO_G G-nibble zero, got=%h", rgb444_out);
            errors = errors + 1;
        end

        // ----- COLOR_ISO B -----
        sw32 = 2'b10;
        settle;
        if (rgb444_out[11:4] !== 8'h00) begin
            $display("FAIL: ISO_B R/G not zero, got=%h", rgb444_out);
            errors = errors + 1;
        end
        if (rgb444_out[3:0] === 4'h0) begin
            $display("FAIL: ISO_B B-nibble zero, got=%h", rgb444_out);
            errors = errors + 1;
        end

        // ----- EDGE on flat field -> 0 -----
        sw_mode = 2'b11;
        sw74    = 4'd1;
        // Need to fill line buffer with consistent luma so all 9 taps == fb_luma
        // pix_valid=1, fb_luma=4 constant. Step h_count + v_count to fill 3 rows.
        begin : fill
            integer yy, xx;
            for (yy = 0; yy < 3; yy = yy + 1) begin
                for (xx = 0; xx < 640; xx = xx + 1) begin
                    @(negedge clk);
                    h_count = xx[9:0];
                    v_count = yy[9:0];
                    @(posedge clk);
                end
            end
        end
        // Now sample at an interior pixel
        h_count = 10'd100;
        v_count = 10'd2;
        settle;
        if (rgb444_out !== 12'h000) begin
            $display("FAIL: EDGE on flat field got=%h, expected 000", rgb444_out);
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS: filter_pipeline 4 modes OK (raw=%h)", raw_sample);
        else begin
            $display("FAIL: %0d errors", errors);
            $finish_and_return(1);
        end
        $finish;
    end
endmodule
