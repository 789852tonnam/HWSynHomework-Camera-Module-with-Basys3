`timescale 1ns/1ps
module dump;
  initial begin
    $dumpfile("C:/Users/78985/Desktop/HW-SynLab2025-main/tests/320/sim_build_frame_buffer/dump.vcd");
    $dumpvars(0, frame_buffer_640x320);
  end
endmodule
