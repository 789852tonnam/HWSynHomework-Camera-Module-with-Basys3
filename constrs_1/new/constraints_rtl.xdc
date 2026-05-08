# constraints_rtl.xdc
# Pin / IO / clock constraints for rtl/top.v (640x480 YCbCr 4:2:2 path).
# Target: Digilent Basys 3 (Xilinx XC7A35T-1CPG236C).
#
# Disable constraints_1/new/constraints.xdc (the 320x240 sources_1/new/top_module.v
# constraints) when activating this file in Vivado.

# =============================================================================
# Board clock: 100 MHz on W5 (MRCC, bank 34)
# =============================================================================
set_property PACKAGE_PIN W5     [get_ports clk_100]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100]
create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports clk_100]

# =============================================================================
# Center button: system reset (BTNC = U18)
# =============================================================================
set_property PACKAGE_PIN U18    [get_ports btnc]
set_property IOSTANDARD LVCMOS33 [get_ports btnc]

# =============================================================================
# Slide switches: SW[15:0]
# =============================================================================
set_property PACKAGE_PIN V17    [get_ports {sw[0]}]
set_property PACKAGE_PIN V16    [get_ports {sw[1]}]
set_property PACKAGE_PIN W16    [get_ports {sw[2]}]
set_property PACKAGE_PIN W17    [get_ports {sw[3]}]
set_property PACKAGE_PIN W15    [get_ports {sw[4]}]
set_property PACKAGE_PIN V15    [get_ports {sw[5]}]
set_property PACKAGE_PIN W14    [get_ports {sw[6]}]
set_property PACKAGE_PIN W13    [get_ports {sw[7]}]
set_property PACKAGE_PIN V2     [get_ports {sw[8]}]
set_property PACKAGE_PIN T3     [get_ports {sw[9]}]
set_property PACKAGE_PIN T2     [get_ports {sw[10]}]
set_property PACKAGE_PIN R3     [get_ports {sw[11]}]
set_property PACKAGE_PIN W2     [get_ports {sw[12]}]
set_property PACKAGE_PIN U1     [get_ports {sw[13]}]
set_property PACKAGE_PIN T1     [get_ports {sw[14]}]
set_property PACKAGE_PIN R2     [get_ports {sw[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[*]}]

# =============================================================================
# LEDs: LD[15:0]
# =============================================================================
set_property PACKAGE_PIN U16    [get_ports {led[0]}]
set_property PACKAGE_PIN E19    [get_ports {led[1]}]
set_property PACKAGE_PIN U19    [get_ports {led[2]}]
set_property PACKAGE_PIN V19    [get_ports {led[3]}]
set_property PACKAGE_PIN W18    [get_ports {led[4]}]
set_property PACKAGE_PIN U15    [get_ports {led[5]}]
set_property PACKAGE_PIN U14    [get_ports {led[6]}]
set_property PACKAGE_PIN V14    [get_ports {led[7]}]
set_property PACKAGE_PIN V13    [get_ports {led[8]}]
set_property PACKAGE_PIN V3     [get_ports {led[9]}]
set_property PACKAGE_PIN W3     [get_ports {led[10]}]
set_property PACKAGE_PIN U3     [get_ports {led[11]}]
set_property PACKAGE_PIN P3     [get_ports {led[12]}]
set_property PACKAGE_PIN N3     [get_ports {led[13]}]
set_property PACKAGE_PIN P1     [get_ports {led[14]}]
set_property PACKAGE_PIN L1     [get_ports {led[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

# =============================================================================
# VGA output (12-bit color via on-board resistor ladder)
# =============================================================================
# Red
set_property PACKAGE_PIN G19    [get_ports {vga_r[0]}]
set_property PACKAGE_PIN H19    [get_ports {vga_r[1]}]
set_property PACKAGE_PIN J19    [get_ports {vga_r[2]}]
set_property PACKAGE_PIN N19    [get_ports {vga_r[3]}]
# Green
set_property PACKAGE_PIN J17    [get_ports {vga_g[0]}]
set_property PACKAGE_PIN H17    [get_ports {vga_g[1]}]
set_property PACKAGE_PIN G17    [get_ports {vga_g[2]}]
set_property PACKAGE_PIN D17    [get_ports {vga_g[3]}]
# Blue
set_property PACKAGE_PIN N18    [get_ports {vga_b[0]}]
set_property PACKAGE_PIN L18    [get_ports {vga_b[1]}]
set_property PACKAGE_PIN K18    [get_ports {vga_b[2]}]
set_property PACKAGE_PIN J18    [get_ports {vga_b[3]}]
# Sync
set_property PACKAGE_PIN P19    [get_ports vga_hsync]
set_property PACKAGE_PIN R19    [get_ports vga_vsync]

set_property IOSTANDARD LVCMOS33 [get_ports {vga_r[*] vga_g[*] vga_b[*] vga_hsync vga_vsync}]

# =============================================================================
# OV7670 camera (Pmod JC + JB header pins per project pinout)
# =============================================================================
# Pixel data D[7:0]
set_property PACKAGE_PIN P17    [get_ports {cam_d[0]}]
set_property PACKAGE_PIN N17    [get_ports {cam_d[1]}]
set_property PACKAGE_PIN M19    [get_ports {cam_d[2]}]
set_property PACKAGE_PIN M18    [get_ports {cam_d[3]}]
set_property PACKAGE_PIN L17    [get_ports {cam_d[4]}]
set_property PACKAGE_PIN K17    [get_ports {cam_d[5]}]
set_property PACKAGE_PIN C16    [get_ports {cam_d[6]}]
set_property PACKAGE_PIN B16    [get_ports {cam_d[7]}]
# Control / sync
set_property PACKAGE_PIN A17    [get_ports cam_href]
set_property PACKAGE_PIN A16    [get_ports cam_pclk]
set_property PACKAGE_PIN B15    [get_ports cam_vsync]
set_property PACKAGE_PIN C15    [get_ports cam_xclk]
set_property PACKAGE_PIN P18    [get_ports cam_rst_n]
set_property PACKAGE_PIN R18    [get_ports cam_pwdn]
# SCCB (I2C-like)
set_property PACKAGE_PIN A14    [get_ports cam_scl]
set_property PACKAGE_PIN A15    [get_ports cam_sda]

set_property IOSTANDARD LVCMOS33 [get_ports {cam_d[*] cam_href cam_pclk cam_vsync cam_xclk cam_rst_n cam_pwdn cam_scl cam_sda}]

# Pull-ups on the open-drain SCCB lines (board has no external pull-ups on these)
set_property PULLUP true        [get_ports cam_scl]
set_property PULLUP true        [get_ports cam_sda]

# =============================================================================
# Camera PCLK is a clock from the OV7670 (~24 MHz when XCLK is 24 MHz, RGB565
# format gives PCLK = 2 * XCLK rate during HREF active for byte streaming —
# treat as 25 MHz worst-case = 40 ns period). It arrives on A16 which is NOT
# a clock-capable pin on Basys 3, so the clock must be routed through general
# fabric. CLOCK_DEDICATED_ROUTE FALSE allows this.
# =============================================================================
create_clock -period 40.000 -name cam_pclk_pin -waveform {0.000 20.000} [get_ports cam_pclk]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets cam_pclk_IBUF]

# =============================================================================
# Clock domain crossings
#   * clk_100 / derived clk_25 / clk_24 (MMCM outputs) form one domain group.
#   * cam_pclk is unrelated to clk_100; cdc_pulse_sync handles the only path
#     that crosses (VSYNC pulse for the LED). Frame buffer crosses clk_pclk
#     (write) and clk_25 (read) but uses a true dual-port BRAM, no timing
#     relationship needed between the two.
# =============================================================================
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks sys_clk] \
    -group [get_clocks cam_pclk_pin]
