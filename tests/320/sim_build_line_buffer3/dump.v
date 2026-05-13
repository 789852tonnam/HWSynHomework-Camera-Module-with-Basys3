`timescale 1ns/1ps
module dump;
  initial begin
    $dumpfile("C:/Users/78985/Desktop/HW-SynLab2025-main/tests/320/sim_build_line_buffer3/dump.vcd");
    $dumpvars(0, line_buffer3);
  end
endmodule
