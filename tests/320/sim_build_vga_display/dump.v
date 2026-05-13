`timescale 1ns/1ps
module dump;
  initial begin
    $dumpfile("C:/Users/78985/Desktop/HW-SynLab2025-main/tests/320/sim_build_vga_display/dump.vcd");
    $dumpvars(0, vga_640x320_display);
  end
endmodule
