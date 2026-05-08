`timescale 1ns/1ps
// 100 MHz -> 25 MHz (VGA pixel) and 24 MHz (camera XCLK).
// Synthesis: MMCME2_BASE on Artix-7. Sim: behavioral clock generators.

module clk_wiz_main (
    input  wire clk_100,
    output wire clk_25,
    output wire clk_24,
    output wire locked
);

`ifdef SYNTHESIS
    // VCO = 100 * 12 / 1 = 1200 MHz (within 600..1600 MHz)
    // CLKOUT0 = 1200 / 48 = 25.000 MHz
    // CLKOUT1 = 1200 / 50 = 24.000 MHz
    wire clkfb;
    wire clk_25_unbuf, clk_24_unbuf;

    MMCME2_BASE #(
        .BANDWIDTH        ("OPTIMIZED"),
        .CLKFBOUT_MULT_F  (12.0),
        .CLKFBOUT_PHASE   (0.0),
        .CLKIN1_PERIOD    (10.0),
        .DIVCLK_DIVIDE    (1),
        .CLKOUT0_DIVIDE_F (48.0),
        .CLKOUT0_PHASE    (0.0),
        .CLKOUT1_DIVIDE   (50),
        .CLKOUT1_PHASE    (0.0),
        .STARTUP_WAIT     ("FALSE")
    ) u_mmcm (
        .CLKIN1   (clk_100),
        .CLKFBIN  (clkfb),
        .CLKFBOUT (clkfb),
        .CLKOUT0  (clk_25_unbuf),
        .CLKOUT1  (clk_24_unbuf),
        .LOCKED   (locked),
        .PWRDWN   (1'b0),
        .RST      (1'b0)
    );

    BUFG u_buf25 (.I(clk_25_unbuf), .O(clk_25));
    BUFG u_buf24 (.I(clk_24_unbuf), .O(clk_24));
`else
    reg clk_25_r = 1'b0;
    reg clk_24_r = 1'b0;
    always #20 clk_25_r = ~clk_25_r;   // 40 ns period = 25 MHz
    always #21 clk_24_r = ~clk_24_r;   // 42 ns period ≈ 23.8 MHz (close enough for sim)
    assign clk_25 = clk_25_r;
    assign clk_24 = clk_24_r;
    assign locked = 1'b1;
`endif

endmodule
