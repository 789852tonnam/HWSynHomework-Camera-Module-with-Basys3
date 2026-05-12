# cocotb testbenches — 640-path (rtl/)
# Usage: make <target>  where target is one of: cam_capture vga_timing filter_pipeline frame_buffer sccb_master ycbcr_to_rgb444 all
#
# Requirements: cocotb >= 2.0, iverilog on PATH.
# Simulator can be overridden: make cam_capture SIM=verilator

SIM            ?= icarus
TOPLEVEL_LANG  ?= verilog
export COCOTB_REDUCED_LOG_FMT ?= 1

ROOT  := $(abspath ../..)
RTL   := $(ROOT)/rtl

COCOTB_MK := $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: cam_capture vga_timing filter_pipeline frame_buffer sccb_master ycbcr_to_rgb444 all clean

cam_capture:
	$(MAKE) -f $(COCOTB_MK) \
		SIM=$(SIM) TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		TOPLEVEL=cam_capture \
		MODULE=test_cam_capture \
		VERILOG_SOURCES="$(RTL)/cam_capture.v" \
		SIM_BUILD=sim_build_cam_capture

vga_timing:
	$(MAKE) -f $(COCOTB_MK) \
		SIM=$(SIM) TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		TOPLEVEL=vga_timing \
		MODULE=test_vga_timing \
		VERILOG_SOURCES="$(RTL)/vga_timing.v" \
		SIM_BUILD=sim_build_vga_timing

filter_pipeline:
	$(MAKE) -f $(COCOTB_MK) \
		SIM=$(SIM) TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		TOPLEVEL=filter_pipeline \
		MODULE=test_filter_pipeline \
		VERILOG_SOURCES="$(RTL)/filter_pipeline.v $(RTL)/ycbcr_to_rgb444.v $(RTL)/line_buffer3.v $(RTL)/filter_edge.v" \
		SIM_BUILD=sim_build_filter_pipeline

frame_buffer:
	$(MAKE) -f $(COCOTB_MK) \
		SIM=$(SIM) TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		TOPLEVEL=frame_buffer \
		MODULE=test_frame_buffer \
		VERILOG_SOURCES="$(RTL)/frame_buffer.v" \
		SIM_BUILD=sim_build_frame_buffer

sccb_master:
	$(MAKE) -f $(COCOTB_MK) \
		SIM=$(SIM) TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		TOPLEVEL=sccb_master \
		MODULE=test_sccb_master \
		VERILOG_SOURCES="$(RTL)/sccb_master.v" \
		COMPILE_ARGS="-P sccb_master.HALF_PER_CYCLES=4" \
		SIM_BUILD=sim_build_sccb_master

ycbcr_to_rgb444:
	$(MAKE) -f $(COCOTB_MK) \
		SIM=$(SIM) TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		TOPLEVEL=ycbcr_to_rgb444 \
		MODULE=test_ycbcr_to_rgb444 \
		VERILOG_SOURCES="$(RTL)/ycbcr_to_rgb444.v" \
		SIM_BUILD=sim_build_ycbcr_to_rgb444

all: cam_capture vga_timing filter_pipeline frame_buffer sccb_master ycbcr_to_rgb444

clean:
	rm -rf sim_build_* results.xml
