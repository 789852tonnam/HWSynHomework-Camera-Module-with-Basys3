#!/bin/tcl
# Add edge filter sources and run synthesis for the Vivado project
# Usage: source C:/HWLab/HW-SynLab2025-main/scripts/add_rtl_and_synth.tcl

puts "Adding line_buffer3.v and filter_edge.v to sources_1 fileset"

# Add the edge filter source files explicitly
add_files -norecurse "C:/HWLab/HW-SynLab2025-main/sources_1/new/line_buffer3.v"
add_files -norecurse "C:/HWLab/HW-SynLab2025-main/sources_1/new/filter_edge.v"

puts "Updating compile order and launching synthesis"
update_compile_order -fileset sources_1

puts "Launching synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1
report_run synth_1

puts "Done. Check the Messages/Log tab for synthesis results."
