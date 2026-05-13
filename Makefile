# OV7670 → Basys 3 → VGA  —  project-level convenience targets
# Requires: cocotb >= 2.0, iverilog on PATH, python-docx (pip install python-docx)

.PHONY: sim sim-640 sim-320 doc clean help

# ── simulation ────────────────────────────────────────────────────────────────

sim: sim-640 sim-320   ## run all cocotb testbenches (640 + 320 paths)

sim-640:               ## run 640-path cocotb tests  (rtl/)
	python tests/640/run_tests.py

sim-320:               ## run 320-path cocotb tests  (sources_1/new/)
	python tests/320/run_tests.py

# ── legacy iverilog testbenches (sim/) ───────────────────────────────────────

sim-legacy-640:        ## compile + run legacy Verilog TBs for 640 path
	iverilog -g2012 -o sim/640/tb_vga_timing.vvp    sim/640/tb_vga_timing.v    rtl/vga_timing.v
	iverilog -g2012 -o sim/640/tb_sccb_master.vvp   sim/640/tb_sccb_master.v   rtl/sccb_master.v
	iverilog -g2012 -o sim/640/tb_frame_buffer.vvp  sim/640/tb_frame_buffer.v  rtl/frame_buffer.v
	iverilog -g2012 -o sim/640/tb_filter_pipeline.vvp \
	    sim/640/tb_filter_pipeline.v \
	    rtl/filter_pipeline.v rtl/ycbcr_to_rgb444.v rtl/line_buffer3.v rtl/filter_edge.v
	for tb in tb_vga_timing tb_sccb_master tb_frame_buffer tb_filter_pipeline; do \
	    vvp sim/640/$$tb.vvp; \
	done

# ── documentation ─────────────────────────────────────────────────────────────

doc:                   ## regenerate documents/demo_ov7670.docx
	python documents/build_doc.py

# ── clean ─────────────────────────────────────────────────────────────────────

clean:                 ## remove cocotb sim_build dirs and results.xml
	rm -rf tests/640/sim_build_* tests/320/sim_build_*
	rm -f sim/640/*.vvp sim/320/*.vvp

# ── help ──────────────────────────────────────────────────────────────────────

help:                  ## show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | \
	    awk 'BEGIN{FS=":.*## "} {printf "  %-20s %s\n", $$1, $$2}'
