`timescale 1ns / 1ps
module tb_edge;
    reg clk = 0;
    always #5 clk = ~clk; // 100 MHz clock (10 ns period)

    reg video_active = 0;
    reg [3:0] raw_r = 0, raw_g = 0, raw_b = 0;
    wire [3:0] edge_out;
    integer pulse_count = 0;

    edge_unit dut(.clk(clk), .raw_r(raw_r), .raw_g(raw_g), .raw_b(raw_b), .video_active(video_active), .edge_out(edge_out));

    always @(posedge clk) begin
        if (video_active && edge_out != 4'h0) begin
            pulse_count = pulse_count + 1;
        end
        $display("%0t active=%0b rgb=%0h%0h%0h edge=%0h", $time, video_active, raw_r, raw_g, raw_b, edge_out);
    end

    initial begin
        $dumpfile("sim/320/edge.vcd");
        $dumpvars(0, tb_edge);

        // Start with blanking
        video_active = 0;
        raw_r = 4'h0; raw_g = 4'h0; raw_b = 4'h0;
        #40;

        // Enter active video and apply a sequence of brightness changes
        video_active = 1;
        // Sequence: 0 -> 4 -> 7 -> 12 -> 12 -> 2 -> 0
        raw_r = 4'h0; raw_g = 4'h0; raw_b = 4'h0; #40;
        raw_r = 4'h4; raw_g = 4'h4; raw_b = 4'h4; #40;
        raw_r = 4'h7; raw_g = 4'h7; raw_b = 4'h7; #40;
        raw_r = 4'hC; raw_g = 4'hC; raw_b = 4'hC; #40;
        raw_r = 4'hC; raw_g = 4'hC; raw_b = 4'hC; #40;
        raw_r = 4'h2; raw_g = 4'h2; raw_b = 4'h2; #40;
        raw_r = 4'h0; raw_g = 4'h0; raw_b = 4'h0; #40;

        // Back to blanking to reset prev_gray
        video_active = 0; #40;

        if (pulse_count < 2) begin
            $display("FAIL: expected at least 2 edge pulses, got %0d", pulse_count);
            $finish_and_return(1);
        end

        $display("PASS: observed %0d edge pulses", pulse_count);

        $finish;
    end
endmodule
