# cocotb testbenches — 320-path (sources_1/new/)
# Usage: make <target>  where target is one of: camera_capture vga_display frame_buffer sccb_config all
#
# Requirements: cocotb >= 2.0, iverilog on PATH.

SIM            ?= icarus
TOPLEVEL_LANG  ?= verilog
export COCOTB_REDUCED_LOG_FMT ?= 1

ROOT  := $(abspath ../..)
SRC   := $(ROOT)/sources_1/new

COCOTB_MK := $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: camera_capture vga_display frame_buffer sccb_config all clean

camera_capture:
	$(MAKE) -f $(COCOTB_MK) \
		SIM=$(SIM) TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		TOPLEVEL=camera_capture_640x320 \
		MODULE=test_camera_capture \
		VERILOG_SOURCES="$(SRC)/camera_capture_640x320.v" \
		SIM_BUILD=sim_build_camera_capture

vga_display:
	$(MAKE) -f $(COCOTB_MK) \
		SIM=$(SIM) TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		TOPLEVEL=vga_640x320_display \
		MODULE=test_vga_display \
		VERILOG_SOURCES="$(SRC)/vga_640x320_display.v" \
		SIM_BUILD=sim_build_vga_display

frame_buffer:
	$(MAKE) -f $(COCOTB_MK) \
		SIM=$(SIM) TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		TOPLEVEL=frame_buffer_640x320 \
		MODULE=test_frame_buffer \
		VERILOG_SOURCES="$(SRC)/frame_buffer_640x320.v" \
		SIM_BUILD=sim_build_frame_buffer

sccb_config:
	$(MAKE) -f $(COCOTB_MK) \
		SIM=$(SIM) TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		TOPLEVEL=sccb_config \
		MODULE=test_sccb_config \
		VERILOG_SOURCES="$(SRC)/sccb_config.v" \
		SIM_BUILD=sim_build_sccb_config

all: camera_capture vga_display frame_buffer sccb_config

clean:
	rm -rf sim_build_* results.xml
