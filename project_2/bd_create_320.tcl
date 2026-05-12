################################################################
# bd_create_320.tcl  —  320-path (sources_1/new/) block design
#
# Usage in Vivado TCL console:
#   source {C:/Users/78985/Desktop/HW-SynLab2025-main/project_2/bd_create_320.tcl}
#
# Notes:
#   - Mode mux FSM (sw[1:0]) is inline RTL in top_module.v — not shown as a BD cell
#   - gray3 = pixel[11:9] (R-channel slice approximation; real design averages R+G+B)
#   - h_edge / v_edge driven by xlconstant=0 (real design computes from pixel_x/y)
#   - After sourcing: Open Block Design in IP Integrator to view / take screenshot
################################################################

set design_name "bd_320_path"

# ── Create BD ───────────────────────────────────────────────────────────────
create_bd_design $design_name
update_compile_order -fileset sources_1
current_bd_design $design_name

# ── Clock IP: clk_wiz_0 (100→25MHz + 24MHz) ────────────────────────────────
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ      {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \
    CONFIG.CLKOUT2_USED      {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {24.000} \
    CONFIG.USE_LOCKED        {false} \
    CONFIG.USE_RESET         {false} \
] [get_bd_cells clk_wiz_0]

# ── RTL modules ─────────────────────────────────────────────────────────────
create_bd_cell -type module -reference sccb_config             sccb_config_0
create_bd_cell -type module -reference camera_capture_640x320  camera_capture_0
create_bd_cell -type module -reference frame_buffer_640x320    frame_buffer_0
create_bd_cell -type module -reference vga_640x320_display     vga_display_0
create_bd_cell -type module -reference line_buffer3            line_buffer_0
create_bd_cell -type module -reference filter_edge             filter_edge_0

# ── Utility IPs ─────────────────────────────────────────────────────────────
# Constant: ov7670_pwdn = 0
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_pwdn
set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {1}] \
    [get_bd_cells const_pwdn]

# Constant: ov7670_rst = 1
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_rst_cam
set_property -dict [list CONFIG.CONST_VAL {1} CONFIG.CONST_WIDTH {1}] \
    [get_bd_cells const_rst_cam]

# Constant: h_edge = 0, v_edge = 0  (boundary check is inline in top_module)
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_hedge
set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {1}] \
    [get_bd_cells const_hedge]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_vedge
set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {1}] \
    [get_bd_cells const_vedge]

# Slice: gray3[2:0] from pixel_12bit[11:9]  (R-channel upper 3 bits)
# Real design: gray3 = avg(R,G,B)[3:1] — approximated here for BD clarity
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_gray3
set_property -dict [list \
    CONFIG.DIN_FROM  {11} \
    CONFIG.DIN_TO    {9}  \
    CONFIG.DIN_WIDTH {12} \
    CONFIG.DOUT_WIDTH {3} \
] [get_bd_cells slice_gray3]

# Slice: threshold[3:0] = sw[3:0]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_threshold
set_property -dict [list \
    CONFIG.DIN_FROM  {3} \
    CONFIG.DIN_TO    {0} \
    CONFIG.DIN_WIDTH {4} \
    CONFIG.DOUT_WIDTH {4} \
] [get_bd_cells slice_threshold]

# ── External ports ──────────────────────────────────────────────────────────
set p_clk100 [create_bd_port -dir I -type clk clk_100mhz]
set_property CONFIG.FREQ_HZ 100000000 $p_clk100

create_bd_port -dir I reset
create_bd_port -dir I -from 3 -to 0 sw

set p_pclk [create_bd_port -dir I -type clk ov7670_pclk]
set_property CONFIG.FREQ_HZ 24000000 $p_pclk

create_bd_port -dir I ov7670_vsync
create_bd_port -dir I ov7670_href
create_bd_port -dir I -from 7 -to 0 ov7670_data

create_bd_port -dir O ov7670_xclk
create_bd_port -dir O ov7670_sioc
create_bd_port -dir IO ov7670_siod
create_bd_port -dir O ov7670_pwdn
create_bd_port -dir O ov7670_rst

create_bd_port -dir O -from 3 -to 0 vga_r
create_bd_port -dir O -from 3 -to 0 vga_g
create_bd_port -dir O -from 3 -to 0 vga_b
create_bd_port -dir O vga_hsync
create_bd_port -dir O vga_vsync

# ── Connections ─────────────────────────────────────────────────────────────

# clk_wiz_0 input
connect_bd_net [get_bd_ports clk_100mhz] [get_bd_pins clk_wiz_0/clk_in1]

# 25 MHz fanout: sccb, frame_buffer(rd), vga, line_buffer
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] \
    [get_bd_pins sccb_config_0/clk] \
    [get_bd_pins frame_buffer_0/clk_r] \
    [get_bd_pins vga_display_0/clk_25m] \
    [get_bd_pins line_buffer_0/clk]

# 24 MHz → camera XCLK
connect_bd_net [get_bd_pins clk_wiz_0/clk_out2] [get_bd_ports ov7670_xclk]

# SCCB → camera config pins
connect_bd_net [get_bd_pins sccb_config_0/sioc] [get_bd_ports ov7670_sioc]
connect_bd_net [get_bd_pins sccb_config_0/siod] [get_bd_ports ov7670_siod]

# Camera capture: pclk shared with frame_buffer write clock
connect_bd_net [get_bd_ports ov7670_pclk] \
    [get_bd_pins camera_capture_0/pclk] \
    [get_bd_pins frame_buffer_0/clk_w]

connect_bd_net [get_bd_ports ov7670_vsync] [get_bd_pins camera_capture_0/vsync]
connect_bd_net [get_bd_ports ov7670_href]  [get_bd_pins camera_capture_0/href]
connect_bd_net [get_bd_ports ov7670_data]  [get_bd_pins camera_capture_0/d_in]

# Capture → frame_buffer write port
connect_bd_net [get_bd_pins camera_capture_0/addr_out] [get_bd_pins frame_buffer_0/addr_w]
connect_bd_net [get_bd_pins camera_capture_0/data_out] [get_bd_pins frame_buffer_0/din]
connect_bd_net [get_bd_pins camera_capture_0/write_en] [get_bd_pins frame_buffer_0/we]

# frame_buffer read → vga (pixel data) + gray3 slice
connect_bd_net [get_bd_pins frame_buffer_0/dout] \
    [get_bd_pins vga_display_0/pixel_in] \
    [get_bd_pins slice_gray3/Din]

# VGA ↔ frame_buffer read address (loop-back)
connect_bd_net [get_bd_pins vga_display_0/frame_addr] [get_bd_pins frame_buffer_0/addr_r]

# VGA → output pins (NORMAL mode path; mode mux inline in top_module)
connect_bd_net [get_bd_pins vga_display_0/vga_r]  [get_bd_ports vga_r]
connect_bd_net [get_bd_pins vga_display_0/vga_g]  [get_bd_ports vga_g]
connect_bd_net [get_bd_pins vga_display_0/vga_b]  [get_bd_ports vga_b]
connect_bd_net [get_bd_pins vga_display_0/hsync]  [get_bd_ports vga_hsync]
connect_bd_net [get_bd_pins vga_display_0/vsync]  [get_bd_ports vga_vsync]

# VGA → line_buffer (pixel coordinates + active)
connect_bd_net [get_bd_pins vga_display_0/active]  [get_bd_pins line_buffer_0/pix_valid]
connect_bd_net [get_bd_pins vga_display_0/pixel_x] [get_bd_pins line_buffer_0/h_count]
connect_bd_net [get_bd_pins vga_display_0/pixel_y] [get_bd_pins line_buffer_0/v_count]

# gray3 slice → line_buffer pixel input
connect_bd_net [get_bd_pins slice_gray3/Dout] [get_bd_pins line_buffer_0/pix_in]
connect_bd_net [get_bd_ports reset]           [get_bd_pins line_buffer_0/rst]

# line_buffer 3×3 taps → filter_edge
foreach tap {top_l top_c top_r mid_l mid_c mid_r bot_l bot_c bot_r} {
    connect_bd_net [get_bd_pins line_buffer_0/$tap] [get_bd_pins filter_edge_0/$tap]
}

# sw → threshold slice → filter_edge
connect_bd_net [get_bd_ports sw]                 [get_bd_pins slice_threshold/Din]
connect_bd_net [get_bd_pins slice_threshold/Dout] [get_bd_pins filter_edge_0/threshold]

# Edge flags (inline combinational in top_module — tied to 0 here)
connect_bd_net [get_bd_pins const_hedge/dout] [get_bd_pins filter_edge_0/h_edge]
connect_bd_net [get_bd_pins const_vedge/dout] [get_bd_pins filter_edge_0/v_edge]

# Constants
connect_bd_net [get_bd_pins const_pwdn/dout]    [get_bd_ports ov7670_pwdn]
connect_bd_net [get_bd_pins const_rst_cam/dout] [get_bd_ports ov7670_rst]

# ── Layout + save ───────────────────────────────────────────────────────────
regenerate_bd_layout
save_bd_design
validate_bd_design

puts ""
puts "================================================================"
puts " Block design created: $design_name"
puts " Open: Flow Navigator > IP Integrator > Open Block Design"
puts "================================================================"
puts " BD limitations (inline RTL not shown as cells):"
puts "   - Mode mux FSM (sw\[1:0\]): NORMAL/EDGE/INVERT/C-ISO"
puts "   - gray3 average: BD uses pixel\[11:9\] slice (R approx)"
puts "   - h_edge/v_edge: tied 0 (real: computed from pixel_x/y)"
puts "================================================================"
