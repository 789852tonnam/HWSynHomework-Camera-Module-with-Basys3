################################################################
# bd_create_640.tcl  —  640-path (rtl/) block design
#
# Usage in Vivado TCL console:
#   source {C:/Users/78985/Desktop/HW-SynLab2025-main/project_2/bd_create_640.tcl}
#
# Notes:
#   - clk_wiz_main is custom RTL (MMCME2_BASE primitive) — shown as RTL cell
#   - sys_rst = btnc_db | ~mmcm_locked: OR logic shown via util_vector_logic
#   - Test pattern generator is inline RTL in top.v — not shown as a BD cell
#   - Two debouncer instances: one for sw[15:0], one for btnc
################################################################

set design_name "bd_640_path"

# ── Create BD ───────────────────────────────────────────────────────────────
create_bd_design $design_name
update_compile_order -fileset sources_1
current_bd_design $design_name

# ── RTL modules ─────────────────────────────────────────────────────────────
create_bd_cell -type module -reference clk_wiz_main    clk_wiz_main_0
create_bd_cell -type module -reference debouncer        debouncer_sw
create_bd_cell -type module -reference debouncer        debouncer_btn
create_bd_cell -type module -reference cam_config       cam_config_0
create_bd_cell -type module -reference cam_capture      cam_capture_0
create_bd_cell -type module -reference frame_buffer     frame_buffer_0
create_bd_cell -type module -reference vga_timing       vga_timing_0
create_bd_cell -type module -reference filter_pipeline  filter_pipeline_0
create_bd_cell -type module -reference cdc_pulse_sync   cdc_pulse_sync_0

# Set debouncer widths
set_property CONFIG.W {16} [get_bd_cells debouncer_sw]
set_property CONFIG.W {1}  [get_bd_cells debouncer_btn]

# ── Utility IPs ─────────────────────────────────────────────────────────────
# NOT gate: ~mmcm_locked
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 not_locked
set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1}] \
    [get_bd_cells not_locked]

# OR gate: sys_rst = btnc_db | ~mmcm_locked
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 or_sys_rst
set_property -dict [list CONFIG.C_OPERATION {or} CONFIG.C_SIZE {1}] \
    [get_bd_cells or_sys_rst]

# Constant 0: rst_src for cdc_pulse_sync
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_zero
set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {1}] \
    [get_bd_cells const_zero]

# Slices for sw_db sub-fields (from debounced sw[15:0])
# sw_mode = sw_db[1:0]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_sw_mode
set_property -dict [list CONFIG.DIN_FROM {1} CONFIG.DIN_TO {0} CONFIG.DIN_WIDTH {16} CONFIG.DOUT_WIDTH {2}] \
    [get_bd_cells slice_sw_mode]

# sw32 = sw_db[3:2]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_sw32
set_property -dict [list CONFIG.DIN_FROM {3} CONFIG.DIN_TO {2} CONFIG.DIN_WIDTH {16} CONFIG.DOUT_WIDTH {2}] \
    [get_bd_cells slice_sw32]

# sw74 = sw_db[7:4]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_sw74
set_property -dict [list CONFIG.DIN_FROM {7} CONFIG.DIN_TO {4} CONFIG.DIN_WIDTH {16} CONFIG.DOUT_WIDTH {4}] \
    [get_bd_cells slice_sw74]

# sw_test_pattern = sw_db[8]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 slice_sw8
set_property -dict [list CONFIG.DIN_FROM {8} CONFIG.DIN_TO {8} CONFIG.DIN_WIDTH {16} CONFIG.DOUT_WIDTH {1}] \
    [get_bd_cells slice_sw8]

# h_edge / v_edge constants (inline in top.v, tied 0 for BD)
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_hedge
set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {1}] [get_bd_cells const_hedge]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 const_vedge
set_property -dict [list CONFIG.CONST_VAL {0} CONFIG.CONST_WIDTH {1}] [get_bd_cells const_vedge]

# ── External ports ──────────────────────────────────────────────────────────
set p_clk100 [create_bd_port -dir I -type clk clk_100]
set_property CONFIG.FREQ_HZ 100000000 $p_clk100

create_bd_port -dir I -from 15 -to 0 sw
create_bd_port -dir I btnc

set p_pclk [create_bd_port -dir I -type clk cam_pclk]
set_property CONFIG.FREQ_HZ 24000000 $p_pclk
create_bd_port -dir I cam_href
create_bd_port -dir I cam_vsync
create_bd_port -dir I -from 7 -to 0 cam_d

create_bd_port -dir O cam_xclk
create_bd_port -dir O cam_rst_n
create_bd_port -dir O cam_pwdn
create_bd_port -dir O cam_scl
create_bd_port -dir IO cam_sda

create_bd_port -dir O vga_hsync
create_bd_port -dir O vga_vsync
create_bd_port -dir O -from 3 -to 0 vga_r
create_bd_port -dir O -from 3 -to 0 vga_g
create_bd_port -dir O -from 3 -to 0 vga_b

create_bd_port -dir O -from 15 -to 0 led

# ── Connections ─────────────────────────────────────────────────────────────

# --- Clock generation ---
connect_bd_net [get_bd_ports clk_100] [get_bd_pins clk_wiz_main_0/clk_100]
connect_bd_net [get_bd_pins clk_wiz_main_0/clk_24] [get_bd_ports cam_xclk]

# ~mmcm_locked
connect_bd_net [get_bd_pins clk_wiz_main_0/locked] [get_bd_pins not_locked/Op1]

# --- Debounce sw[15:0] ---
connect_bd_net [get_bd_pins clk_wiz_main_0/clk_25] [get_bd_pins debouncer_sw/clk]
connect_bd_net [get_bd_ports sw] [get_bd_pins debouncer_sw/sw_in]

# --- Debounce btnc ---
connect_bd_net [get_bd_pins clk_wiz_main_0/clk_25] [get_bd_pins debouncer_btn/clk]
connect_bd_net [get_bd_ports btnc] [get_bd_pins debouncer_btn/sw_in]

# sys_rst = btnc_db | ~locked
connect_bd_net [get_bd_pins debouncer_btn/sw_out] [get_bd_pins or_sys_rst/Op1]
connect_bd_net [get_bd_pins not_locked/Res]       [get_bd_pins or_sys_rst/Op2]

# --- sw slice sub-fields ---
connect_bd_net [get_bd_pins debouncer_sw/sw_out] \
    [get_bd_pins slice_sw_mode/Din] \
    [get_bd_pins slice_sw32/Din] \
    [get_bd_pins slice_sw74/Din] \
    [get_bd_pins slice_sw8/Din]

# --- cam_config ---
connect_bd_net [get_bd_pins clk_wiz_main_0/clk_25] [get_bd_pins cam_config_0/clk]
connect_bd_net [get_bd_pins or_sys_rst/Res]         [get_bd_pins cam_config_0/rst]
connect_bd_net [get_bd_pins slice_sw8/Dout]         [get_bd_pins cam_config_0/test_pattern_en]
connect_bd_net [get_bd_pins cam_config_0/cam_rst_n] [get_bd_ports cam_rst_n]
connect_bd_net [get_bd_pins cam_config_0/cam_pwdn]  [get_bd_ports cam_pwdn]
connect_bd_net [get_bd_pins cam_config_0/scl]       [get_bd_ports cam_scl]
connect_bd_net [get_bd_pins cam_config_0/sda]       [get_bd_ports cam_sda]

# --- cam_capture ---
connect_bd_net [get_bd_ports cam_pclk]  [get_bd_pins cam_capture_0/pclk_in]
connect_bd_net [get_bd_ports cam_d]     [get_bd_pins cam_capture_0/d_in]
connect_bd_net [get_bd_ports cam_href]  [get_bd_pins cam_capture_0/href]
connect_bd_net [get_bd_ports cam_vsync] [get_bd_pins cam_capture_0/vsync]

# --- frame_buffer ---
# Write port (pclk domain)
connect_bd_net [get_bd_ports cam_pclk]                    [get_bd_pins frame_buffer_0/wr_clk]
connect_bd_net [get_bd_pins cam_capture_0/wr_en]          [get_bd_pins frame_buffer_0/wr_en]
connect_bd_net [get_bd_pins cam_capture_0/wr_chroma_en]   [get_bd_pins frame_buffer_0/wr_chroma_en]
connect_bd_net [get_bd_pins cam_capture_0/wr_addr]        [get_bd_pins frame_buffer_0/wr_addr]
connect_bd_net [get_bd_pins cam_capture_0/wr_luma]        [get_bd_pins frame_buffer_0/wr_luma]
connect_bd_net [get_bd_pins cam_capture_0/wr_chroma]      [get_bd_pins frame_buffer_0/wr_chroma]

# Read port (25MHz domain)
connect_bd_net [get_bd_pins clk_wiz_main_0/clk_25] [get_bd_pins frame_buffer_0/rd_clk]
connect_bd_net [get_bd_pins vga_timing_0/rd_addr]  [get_bd_pins frame_buffer_0/rd_addr]

# --- vga_timing ---
connect_bd_net [get_bd_pins clk_wiz_main_0/clk_25] [get_bd_pins vga_timing_0/clk]
connect_bd_net [get_bd_pins or_sys_rst/Res]         [get_bd_pins vga_timing_0/rst]
connect_bd_net [get_bd_pins vga_timing_0/hsync]     [get_bd_ports vga_hsync]
connect_bd_net [get_bd_pins vga_timing_0/vsync]     [get_bd_ports vga_vsync]

# --- filter_pipeline ---
connect_bd_net [get_bd_pins clk_wiz_main_0/clk_25] [get_bd_pins filter_pipeline_0/clk]
connect_bd_net [get_bd_pins or_sys_rst/Res]         [get_bd_pins filter_pipeline_0/rst]
connect_bd_net [get_bd_pins frame_buffer_0/rd_luma]   [get_bd_pins filter_pipeline_0/fb_luma]
connect_bd_net [get_bd_pins frame_buffer_0/rd_chroma] [get_bd_pins filter_pipeline_0/fb_chroma]
connect_bd_net [get_bd_pins vga_timing_0/h_count]    [get_bd_pins filter_pipeline_0/h_count]
connect_bd_net [get_bd_pins vga_timing_0/v_count]    [get_bd_pins filter_pipeline_0/v_count]
connect_bd_net [get_bd_pins vga_timing_0/active_video] [get_bd_pins filter_pipeline_0/pix_valid]
connect_bd_net [get_bd_pins slice_sw_mode/Dout]      [get_bd_pins filter_pipeline_0/sw_mode]
connect_bd_net [get_bd_pins slice_sw32/Dout]         [get_bd_pins filter_pipeline_0/sw32]
connect_bd_net [get_bd_pins slice_sw74/Dout]         [get_bd_pins filter_pipeline_0/sw74]
connect_bd_net [get_bd_pins const_hedge/dout]        [get_bd_pins filter_pipeline_0/h_edge]
connect_bd_net [get_bd_pins const_vedge/dout]        [get_bd_pins filter_pipeline_0/v_edge]

# filter → VGA output (pipeline 3-cycle delay is inline in top.v)
connect_bd_net [get_bd_pins filter_pipeline_0/rgb444_out] [get_bd_ports vga_r]
# NOTE: In real top.v, vga_r = active_d ? filter_out[11:8] : 4'h0
# This BD connects rgb444_out directly (gating logic inline in top.v not shown)

# --- cdc_pulse_sync: vsync_pulse pclk→25MHz ---
connect_bd_net [get_bd_ports cam_pclk]               [get_bd_pins cdc_pulse_sync_0/clk_src]
connect_bd_net [get_bd_pins clk_wiz_main_0/clk_25]  [get_bd_pins cdc_pulse_sync_0/clk_dst]
connect_bd_net [get_bd_pins const_zero/dout]         [get_bd_pins cdc_pulse_sync_0/rst_src]
connect_bd_net [get_bd_pins or_sys_rst/Res]          [get_bd_pins cdc_pulse_sync_0/rst_dst]
connect_bd_net [get_bd_pins cam_capture_0/vsync_pulse] [get_bd_pins cdc_pulse_sync_0/pulse_in]
# pulse_out → led_frame_toggle (inline FF in top.v, not shown as BD cell)

# cam_config status → LED[15:8]  (inline assign in top.v, not shown as BD cell)
# For BD: leave led port unconnected or tie const for now
# connect_bd_net [get_bd_pins cam_config_0/cfg_done] ...

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
puts "   - Test pattern generator (sw\[9\]): inline always block in top.v"
puts "   - active_pipe 3-cycle delay + VGA gating: inline in top.v"
puts "   - led_frame_toggle FF: inline in top.v"
puts "   - LED assignments: inline assign in top.v"
puts "   - h_edge/v_edge: tied 0 (real: h_count==0||>=638, v_count<2||>=479)"
puts "   - vga_r/g/b tied to rgb444_out[11:8/7:4/3:0] — add xlslice if needed"
puts "================================================================"
