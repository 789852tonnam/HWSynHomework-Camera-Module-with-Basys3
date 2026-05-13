`timescale 1ns/1ps
module dump;
  initial begin
    $dumpfile("C:/Users/78985/Desktop/HW-SynLab2025-main/tests/640/sim_build_filter_pipeline/dump.vcd");
    $dumpvars(0, filter_pipeline);
  end
endmodule
