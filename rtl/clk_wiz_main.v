`timescale 1ns/1ps
// clk_wiz_main.v
// Behavioral wrapper for Vivado Clocking Wizard IP (MMCM).
//
// In Vivado: regenerate this file as an IP-generated wrapper.
// For simulation/synthesis fallback: this module uses MMCME2_BASE primitive
// to produce clk_25 (25 MHz) and clk_24 (24 MHz) from clk_100 (100 MHz).
//
// IMPORTANT FOR SYNTHESIS:
// Replace this file with the Vivado IP-generated wrapper
// (Project → IP Catalog → Clocking Wizard) configured as:
//   Input: 100 MHz
//   Output 1: 25.000 MHz (VGA pixel clock)
//   Output 2: 24.000 MHz (camera XCLK)
// The IP will generate a .xci file and a wrapper.

module clk_wiz_main (
    input  wire clk_100,    // 100 MHz board clock (pin W5)
    output wire clk_25,     // 25 MHz VGA/read clock
    output wire clk_24,     // 24 MHz camera XCLK
    output wire locked      // MMCM locked flag
);

`ifdef SYNTHESIS
    // Synthesis: use MMCME2_BASE primitive
    // Parameters for 100 MHz → 25 MHz and 24 MHz:
    //   VCO = 100 MHz * CLKFBOUT_MULT_F / DIVCLK_DIVIDE
    //       = 100 * 12 / 1 = 1200 MHz (within 800-1600 MHz range)
    //   clk_25: 1200 / 48 = 25.000 MHz
    //   clk_24: 1200 / 50 = 24.000 MHz
    wire clkfb;
    wire clk_25_unbuf, clk_24_unbuf;

    MMCME2_BASE #(
        .BANDWIDTH        ("OPTIMIZED"),
        .CLKFBOUT_MULT_F  (12.0),
        .CLKFBOUT_PHASE   (0.0),
        .CLKIN1_PERIOD    (10.0),        // 100 MHz = 10 ns
        .DIVCLK_DIVIDE    (1),
        .CLKOUT0_DIVIDE_F (48.0),        // 25.000 MHz
        .CLKOUT0_PHASE    (0.0),
        .CLKOUT1_DIVIDE   (50),          // 24.000 MHz
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
    // Simulation behavioral model
    reg clk_25_r = 1'b0;
    reg clk_24_r = 1'b0;

    // 25 MHz: period = 40 ns (half-period = 20 ns)
    always begin
        #20 clk_25_r = 1'b1;
        #20 clk_25_r = 1'b0;
    end

    // 24 MHz: period ~41.67 ns (use 21ns half-period ≈ ~23.8 MHz, close enough for sim)
    always begin
        #21 clk_24_r = 1'b1;
        #21 clk_24_r = 1'b0;
    end

    assign clk_25 = clk_25_r;
    assign clk_24 = clk_24_r;
    assign locked = 1'b1;
`endif

endmodule
