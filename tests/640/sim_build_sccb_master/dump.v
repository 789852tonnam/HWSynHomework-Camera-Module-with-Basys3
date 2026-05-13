`timescale 1ns/1ps
module dump;
  initial begin
    $dumpfile("C:/Users/78985/Desktop/HW-SynLab2025-main/tests/640/sim_build_sccb_master/dump.vcd");
    $dumpvars(0, sccb_master);
  end
endmodule
