#!/bin/tcl
# Complete fix: close old synthesis, add edge filter sources, rerun synthesis
# Usage: source C:/HWLab/HW-SynLab2025-main/scripts/fix_and_synth.tcl

puts "=== Closing old synthesis run ==="
close_run synth_1

puts "=== Removing old clk_wiz_0 checkpoint ==="
catch {remove_files -fileset sources_1 "C:/HWLab/HW-SynLab2025-main/sources_1/ip/clk_wiz_0/clk_wiz_0.xci"}

puts "=== Adding edge filter source files to fileset sources_1 ==="
add_files -norecurse "C:/HWLab/HW-SynLab2025-main/sources_1/new/line_buffer3.v"
add_files -norecurse "C:/HWLab/HW-SynLab2025-main/sources_1/new/filter_edge.v"

puts "=== Updating compile order ==="
update_compile_order -fileset sources_1

puts "=== Launching synthesis ==="
launch_runs synth_1 -jobs 4
wait_on_run synth_1

puts "=== Synthesis complete ==="
report_run synth_1
