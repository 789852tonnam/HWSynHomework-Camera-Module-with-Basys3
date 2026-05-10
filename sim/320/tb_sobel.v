`timescale 1ns / 1ps
module tb_sobel;
    reg clk = 0;
    always #5 clk = ~clk;

    reg reset = 1;
    reg active = 0;
    reg [9:0] pixel_x = 0;
    reg [9:0] pixel_y = 0;
    reg [11:0] pixel_in = 0;
    wire [3:0] edge_out;

    sobel_edge_filter dut(
        .clk(clk), .reset(reset), .active(active),
        .pixel_x(pixel_x), .pixel_y(pixel_y),
        .pixel_in(pixel_in), .edge_out(edge_out)
    );

    integer edge_pulses = 0;
    integer x;
    integer y;

    always @(posedge clk) begin
        if (active && edge_out != 4'h0) begin
            edge_pulses = edge_pulses + 1;
        end
    end

    task drive_pixel;
        input [9:0] x_in;
        input [9:0] y_in;
        input [11:0] pixel;
        begin
            pixel_x = x_in;
            pixel_y = y_in;
            pixel_in = pixel;
            @(posedge clk);
        end
    endtask

    initial begin
        $dumpfile("sim/320/sobel.vcd");
        $dumpvars(0, tb_sobel);

        repeat (2) @(posedge clk);
        reset = 0;
        active = 1;

        // Simple 6x6 synthetic image with a vertical step edge:
        // left half dark, right half bright.
        for (y = 0; y < 6; y = y + 1) begin
            for (x = 0; x < 6; x = x + 1) begin
                if (x < 3) begin
                    drive_pixel(x[9:0], y[9:0], 12'h111);
                end else begin
                    drive_pixel(x[9:0], y[9:0], 12'hEEE);
                end
            end
        end

        active = 0;
        repeat (2) @(posedge clk);

        if (edge_pulses == 0) begin
            $display("FAIL: Sobel produced no edge pulses");
            $finish_and_return(1);
        end

        $display("PASS: Sobel produced %0d edge pulses", edge_pulses);
        $finish;
    end
endmodule
