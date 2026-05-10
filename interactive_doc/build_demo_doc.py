"""
Build demo .docx for OV7670 -> VGA project, mirroring the structure of the
provided demo-1031643 reference document.

Run:
    python build_demo_doc.py
Output:
    demo_ov7670.docx in the same folder.
"""

from pathlib import Path
from docx import Document
from docx.shared import Pt, RGBColor, Inches, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.oxml import OxmlElement


REPO_ROOT = Path(__file__).resolve().parent.parent
RTL_DIR = REPO_ROOT / "rtl"
SIM_DIR = REPO_ROOT / "sim"
OUT_PATH = Path(__file__).resolve().parent / "demo_ov7670.docx"


def set_cell_shading(cell, hex_fill):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hex_fill)
    tc_pr.append(shd)


def add_heading(doc, text, level=1):
    h = doc.add_heading(text, level=level)
    for run in h.runs:
        run.font.color.rgb = RGBColor(0, 0, 0)
    return h


def add_para(doc, text, bold=False, italic=False, size=11):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.bold = bold
    run.italic = italic
    run.font.size = Pt(size)
    return p


def add_bullet(doc, text, level=0):
    p = doc.add_paragraph(text, style="List Bullet")
    p.paragraph_format.left_indent = Inches(0.25 + 0.25 * level)
    return p


def add_code_block(doc, code_text, title=None):
    if title:
        p = doc.add_paragraph()
        run = p.add_run(title)
        run.bold = True
        run.font.size = Pt(10)

    table = doc.add_table(rows=1, cols=1)
    table.autofit = False
    cell = table.cell(0, 0)
    set_cell_shading(cell, "F4F4F4")
    cell.text = ""
    para = cell.paragraphs[0]
    para.paragraph_format.space_after = Pt(0)
    para.paragraph_format.space_before = Pt(0)
    run = para.add_run(code_text)
    run.font.name = "Consolas"
    run.font.size = Pt(8)
    rPr = run._element.get_or_add_rPr()
    rFonts = OxmlElement("w:rFonts")
    rFonts.set(qn("w:ascii"), "Consolas")
    rFonts.set(qn("w:hAnsi"), "Consolas")
    rPr.append(rFonts)
    return table


def add_qa(doc, question, answer):
    p = doc.add_paragraph()
    p.paragraph_format.left_indent = Inches(0.25)
    r1 = p.add_run("- " + question + "\n")
    r1.bold = True
    r1.font.size = Pt(11)
    r2 = p.add_run("    Answer: " + answer)
    r2.font.size = Pt(11)


def read_rtl(name):
    return (RTL_DIR / name).read_text(encoding="utf-8", errors="replace")


def read_sim(name):
    return (SIM_DIR / name).read_text(encoding="utf-8", errors="replace")


def add_tb_section(doc, filename, description, pass_line, verifies):
    add_heading(doc, f"Testbench : {Path(filename).stem}", level=2)
    add_para(doc, "Module under test + what is verified:", bold=True, size=11)
    add_para(doc, description, size=11)
    add_para(doc, "Specific checks:", bold=True, size=11)
    for v in verifies:
        add_bullet(doc, v)
    add_para(doc, "Testbench source:", bold=True, size=11)
    code = read_sim(filename)
    add_code_block(doc, code)
    add_para(doc, "Simulation result (iverilog -g2012 + vvp):", bold=True, size=11)
    add_code_block(doc, pass_line)
    doc.add_paragraph()


def add_module_section(doc, filename, description):
    add_heading(doc, f"Module : {Path(filename).stem}", level=2)
    add_para(doc, "Module code:", bold=True, size=11)
    code = read_rtl(filename)
    add_code_block(doc, code)
    add_para(doc, "Module Description:", bold=True, size=11)
    add_para(doc, description, size=11)
    doc.add_paragraph()


def build():
    doc = Document()

    style = doc.styles["Normal"]
    style.font.name = "Calibri"
    style.font.size = Pt(11)

    # ---------------- Cover ----------------
    add_heading(doc, "Group Member", level=1)
    add_para(doc, "Group name : ____________________", bold=True)

    table = doc.add_table(rows=5, cols=2)
    table.style = "Light Grid Accent 1"
    hdr = table.rows[0].cells
    hdr[0].text = "Name"
    hdr[1].text = "Student Number"
    for i in range(1, 5):
        table.rows[i].cells[0].text = "____________________"
        table.rows[i].cells[1].text = "____________________"
    doc.add_paragraph()

    # ---------------- Phase 1 / Filter Summary ----------------
    add_heading(doc, "Phase 1 Summary - Filter Selection", level=1)
    add_para(
        doc,
        "Per the project rubric (3 distinct hardware-based filters, "
        "togglable in real-time via Basys 3 slide switches), this group "
        "implemented the following:",
    )
    add_bullet(
        doc,
        "Color Inversion (Negative) - bitwise NOT of the decoded RGB444 "
        "output. Selected via SW[1:0] = 2'b01.",
    )
    add_bullet(
        doc,
        "Color Channel Isolation - pass-through of a single R / G / B "
        "channel chosen by SW[3:2]. Selected via SW[1:0] = 2'b10.",
    )
    add_bullet(
        doc,
        "Sobel Edge Detection - 3x3 convolution on luma (Y3) using a "
        "line buffer, with threshold tunable via SW[7:4]. Selected via "
        "SW[1:0] = 2'b11.",
    )
    add_para(
        doc,
        "SW[1:0] = 2'b00 displays the raw decoded video stream "
        "(YCbCr 4:2:2 -> RGB444 with 2x2 Bayer dither).",
    )
    doc.add_paragraph()

    # ---------------- Block diagram ----------------
    add_heading(doc, "Overall Design Block Diagram", level=1)
    add_para(
        doc,
        "Real-time 640x480 video pipeline on Basys 3 + OV7670. "
        "Pixels stream from the camera at 24 MHz, get quantized to "
        "YCbCr 4:2:2 (Y3 + Cb2/Cr2) for BRAM storage, and are read "
        "back at 25 MHz for VGA output through a filter pipeline.",
    )

    pipeline = (
        "  clk_100 (Basys3 crystal)\n"
        "      |\n"
        "      v\n"
        "  clk_wiz_main  (MMCM)  ----> clk_25 (VGA pixel + logic)\n"
        "                        ----> clk_24 (cam XCLK)\n"
        "                                |\n"
        "                                v\n"
        "  OV7670 sensor\n"
        "      |  RGB565 (2 bytes/px) over D[7:0], pclk, href, vsync\n"
        "      v\n"
        "  cam_capture   RGB565 -> YCbCr 4:2:2  (Y3, Cb2, Cr2)\n"
        "      |\n"
        "      v\n"
        "  frame_buffer  split BRAM:  luma (3-bit, 307200) + chroma (4-bit, 153600)\n"
        "      |  read @ clk_25\n"
        "      v\n"
        "  filter_pipeline   RAW / INVERT / COLOR_ISO / EDGE\n"
        "      |    (line_buffer3 + filter_edge for Sobel)\n"
        "      v\n"
        "  ycbcr_to_rgb444  + dither + clamp\n"
        "      |\n"
        "      v\n"
        "  vga_timing  ->  HSYNC/VSYNC + RGB444 to VGA pins\n"
        "\n"
        "  SCCB side (one-shot at boot):\n"
        "  cam_config (77-entry register ROM) -> sccb_master -> SIOC/SIOD -> OV7670\n"
    )
    add_code_block(doc, pipeline, title="Pipeline overview")

    # ---------------- Design Decision ----------------
    add_heading(doc, "Design Decision", level=1)

    add_heading(doc, "1. Module Architecture", level=2)
    add_qa(
        doc,
        "Why did you structure your design this way?",
        "Each functional block lives in its own file (cam_capture, "
        "frame_buffer, filter_pipeline, ycbcr_to_rgb444, sccb_master, "
        "vga_timing). Clock-domain boundaries (cam_pclk vs clk_25) are "
        "isolated to specific modules so that timing constraints stay "
        "simple. The top-level only wires everything together and owns "
        "the reset-and-config FSM.",
    )
    add_qa(
        doc,
        "What are the advantages of using this approach?",
        "Modularity makes it easy to swap implementations (e.g. RGB444 "
        "vs YCbCr 4:2:2 storage), debug each stage in isolation with a "
        "dedicated testbench, and reason about clock-domain crossings "
        "since they are confined to frame_buffer and cdc_pulse_sync.",
    )

    add_heading(doc, "2. Communication Protocols", level=2)
    add_qa(
        doc,
        "Why did you choose this specific protocol for communication?",
        "SCCB (Serial Camera Control Bus, OmniVision-defined, ~95% "
        "I2C-compatible) is the only configuration interface OV7670 "
        "exposes, so it is mandatory for setting RGB565 output, "
        "resolution, gain, and AWB. The pixel data path itself is a "
        "synchronous parallel bus (PCLK / HREF / VSYNC / D[7:0]).",
    )
    add_qa(
        doc,
        "How does this protocol suit your design requirements?",
        "Configuration is one-shot and slow (about 100 kHz SCCB), so "
        "bit-banging it from clk_25 is cheap and never gets in the way "
        "of the high-throughput pixel bus. The parallel bus on the "
        "data side gives one byte per PCLK with no protocol overhead, "
        "which matches the 25 MHz fill rate VGA needs.",
    )

    add_heading(doc, "3. Clock and Data Transfer Rate", level=2)
    add_qa(
        doc,
        "Why did you select this specific clock frequency?",
        "Two clocks are derived by the MMCM from the 100 MHz board "
        "crystal: 25.000 MHz for VGA pixel + main logic (matches the "
        "VESA 640x480@60 timing) and 24.000 MHz for the camera XCLK "
        "(OV7670 datasheet typical). The frame buffer is dual-clock "
        "(write @ 24 MHz, read @ 25 MHz) so each domain runs at its "
        "native rate.",
    )
    add_qa(
        doc,
        "How does the data rate impact system performance?",
        "VGA at 25 MHz consumes one pixel per cycle = 60 frames/sec. "
        "OV7670 streams ~30 fps at 24 MHz XCLK. Because the frame "
        "buffer decouples producer and consumer, brief rate "
        "differences are absorbed without tearing. Heavy math (BT.601 "
        "luma multiply, Sobel) sits on the read side at 25 MHz, "
        "leaving the camera side (write side) light.",
    )
    add_qa(
        doc,
        "Did you consider constraints such as FPGA timing, external "
        "device compatibility, or noise margins?",
        "Yes. Both 24 MHz and 25 MHz come from the same MMCM VCO "
        "(1200 MHz) so they share a known phase relationship; CDC is "
        "still treated explicitly via a dual-port BRAM and "
        "cdc_pulse_sync for VSYNC. SCCB is held at ~100 kHz to stay "
        "well within OV7670 spec and to tolerate breadboard pull-up "
        "tolerances.",
    )

    add_heading(doc, "4. Resource Utilization", level=2)
    add_qa(
        doc,
        "How does your design balance resource usage (LUTs, FFs, "
        "BRAMs) and performance?",
        "The 640x480 frame would not fit in BRAM at full RGB565 (16 "
        "bpp -> 4.9 Mb), so the design quantizes to YCbCr 4:2:2 with "
        "Y3 + Cb2 + Cr2 = 5 bits/pixel = 1.54 Mb total. Luma uses ~30 "
        "BRAM36 tiles, chroma ~20, hitting full utilization on "
        "XC7A35T. LUTs are spent on the BT.601 multiply on the write "
        "side and on the Sobel kernel + threshold on the read side. "
        "FFs hold pipeline registers and the SCCB FSM.",
    )
    add_qa(
        doc,
        "Why did you optimize certain parts of the design?",
        "Hot paths are the per-pixel converter (write side) and the "
        "Sobel + line buffer (read side). Y is computed combinationally "
        "from RGB, then registered before BRAM. The Cb/Cr 4-bin "
        "quantizer keeps thresholds antisymmetric (-48, 0, +48) so a "
        "neutral pixel round-trips back to neutral. The decoder uses "
        "small case-statement LUTs for r_off/b_off/g_off, sums + "
        "clamps to RGB444, no DSPs needed on the read side.",
    )

    # ---------------- Implementation Detail ----------------
    add_heading(doc, "Implementation Detail", level=1)

    add_module_section(
        doc,
        "top.v",
        "Top-level wrapper. Instantiates the MMCM (clk_25 + clk_24), "
        "debouncer, sccb_master + cam_config, cam_capture, "
        "frame_buffer, filter_pipeline (which embeds line_buffer3, "
        "filter_edge, and ycbcr_to_rgb444), and vga_timing. Owns the "
        "reset hold / camera power-up sequence and routes SW[15:0] "
        "into per-module mode and threshold inputs.",
    )

    add_module_section(
        doc,
        "clk_wiz_main.v",
        "Wraps an MMCME2_BASE primitive (synthesis) or behavioural "
        "clock generators (simulation). Produces clk_25 (VGA pixel) "
        "and clk_24 (camera XCLK) from a single 100 MHz board input. "
        "VCO = 100 * 12 / 1 = 1200 MHz; CLKOUT0 / 48 = 25 MHz, "
        "CLKOUT1 / 50 = 24 MHz. Outputs LOCKED for downstream reset.",
    )

    add_module_section(
        doc,
        "cam_config.v",
        "Boot-time SCCB sequencer. Drives cam_rst_n through a hold + "
        "release schedule, then walks a 77-entry register-write ROM "
        "(COM7 = RGB output, COM15 = RGB565 full range, plus AWB / "
        "gamma / scaling). Issues one 16-bit {reg, value} command at "
        "a time to sccb_master and waits for done before advancing.",
    )

    add_module_section(
        doc,
        "sccb_master.v",
        "Bit-banged SCCB / 3-wire master. Generates START, byte "
        "transfers (device address 0x42 + W, register address, data) "
        "and STOP on SIOC / SIOD. Treats the 9th bit of each byte as "
        "don't-care per SCCB spec. Runs at ~100 kHz divided down from "
        "clk_25 to stay within OV7670 datasheet limits.",
    )

    add_module_section(
        doc,
        "cam_capture.v",
        "Pixel ingest in cam_pclk domain. Captures RGB565 in two "
        "halves on consecutive HREF cycles (b1, then full pix16), "
        "extracts R5/G6/B5, bit-replicates to 8-bit channels, "
        "computes BT.601 luma (Y = (77R + 150G + 29B) / 256), and "
        "quantizes diff_b = B-Y and diff_r = R-Y into 4 bins each "
        "(Cb2, Cr2). Writes Y per pixel and Cb/Cr only on even "
        "columns into the frame buffer.",
    )

    add_module_section(
        doc,
        "frame_buffer.v",
        "Split dual-clock storage for YCbCr 4:2:2. luma_mem holds "
        "307,200 entries x 3 bits, chroma_mem holds 153,600 entries x "
        "4 bits (chroma shared across each horizontal pair). Writes "
        "are clocked by cam_pclk (24 MHz), reads by clk_25; the "
        "block-RAM dual-port primitives handle the CDC.",
    )

    add_module_section(
        doc,
        "ycbcr_to_rgb444.v",
        "Read-side decoder. Appends a Bayer 2x2 dither bit "
        "(h_pos XOR v_pos) to the 3-bit luma to get Y4. Looks up "
        "antisymmetric R/B/G offsets from Cb2 / Cr2 (-3, -1, +1, "
        "+3 for strong/mild bins), sums to Y4, clamps to 4 bits, and "
        "outputs 12-bit RGB444 to the VGA pins.",
    )

    add_module_section(
        doc,
        "filter_pipeline.v",
        "Read-side mode mux. SW[1:0] selects RAW (passthrough), "
        "INVERT (XOR 0xFFF), COLOR_ISO (gate channels by SW[3:2]), "
        "or EDGE (Sobel-on-luma -> white-on-black mask). Drives "
        "line_buffer3 + filter_edge for the EDGE mode.",
    )

    add_module_section(
        doc,
        "line_buffer3.v",
        "Three-row sliding window for 2D filters. Shifts incoming Y "
        "samples through three BRAM-backed line stores so that "
        "filter_edge sees a 3x3 neighbourhood per cycle.",
    )

    add_module_section(
        doc,
        "filter_edge.v",
        "Sobel edge detector on luma. Computes Gx (horizontal) + Gy "
        "(vertical) gradients, approximates magnitude as |Gx| + |Gy| "
        "(cheap vs sqrt), and thresholds against SW[7:4] to produce a "
        "1-bit edge mask, which is then expanded into white pixels at "
        "the VGA stage.",
    )

    add_module_section(
        doc,
        "vga_timing.v",
        "VESA 640x480 @ 60 Hz timing generator (H total 800, V total "
        "525, 25 MHz pixel clock). Produces hsync/vsync (active low), "
        "video_on, and 10-bit pixel x/y for downstream addressing of "
        "the frame buffer.",
    )

    add_module_section(
        doc,
        "debouncer.v",
        "Standard counter-based debouncer used for switches and the "
        "centre button. Filters glitches shorter than the debounce "
        "period before downstream logic samples the signal.",
    )

    add_module_section(
        doc,
        "cdc_pulse_sync.v",
        "Single-pulse CDC synchronizer. Used to bring the camera "
        "VSYNC pulse from cam_pclk into clk_25 so a frame-rate LED "
        "can blink without metastability.",
    )

    # ---------------- Simulation & Testbenches ----------------
    add_heading(doc, "Simulation & Testbenches", level=1)
    add_para(
        doc,
        "Per the rubric (5 pts), each major module has a dedicated "
        "testbench. All of the testbenches below compile and pass "
        "under Icarus Verilog (iverilog -g2012). VCD waveforms are "
        "produced in sim/*.vcd and viewable with GTKWave for the "
        "presentation.",
    )
    add_para(
        doc,
        "How to run all testbenches:",
        bold=True,
    )
    run_cmds = (
        "# ---- 640 path (rtl/) ----\n"
        "iverilog -g2012 -o sim/640/tb_vga_timing.vvp     sim/640/tb_vga_timing.v     rtl/vga_timing.v\n"
        "iverilog -g2012 -o sim/640/tb_sccb_master.vvp    sim/640/tb_sccb_master.v    rtl/sccb_master.v\n"
        "iverilog -g2012 -o sim/640/tb_frame_buffer.vvp   sim/640/tb_frame_buffer.v   rtl/frame_buffer.v\n"
        "iverilog -g2012 -o sim/640/tb_filter_pipeline.vvp sim/640/tb_filter_pipeline.v \\\n"
        "    rtl/filter_pipeline.v rtl/ycbcr_to_rgb444.v rtl/line_buffer3.v rtl/filter_edge.v\n"
        "for tb in tb_vga_timing tb_sccb_master tb_frame_buffer tb_filter_pipeline; do\n"
        "    vvp sim/640/$tb.vvp\n"
        "done\n"
        "\n"
        "# ---- 320 path (sources_1/new/) ----\n"
        "iverilog -g2012 -o sim/320/tb_vga_640x320_display.vvp sim/320/tb_vga_640x320_display.v \\\n"
        "    sources_1/new/vga_640x320_display.v\n"
        "iverilog -g2012 -o sim/320/tb_sccb_config.vvp sim/320/tb_sccb_config.v \\\n"
        "    sources_1/new/sccb_config.v\n"
        "iverilog -g2012 -o sim/320/tb_frame_buffer_640x320.vvp sim/320/tb_frame_buffer_640x320.v \\\n"
        "    sources_1/new/frame_buffer_640x320.v\n"
        "iverilog -g2012 -o sim/320/tb_edge.vvp  sim/320/tb_edge.v  sim/320/edge_unit.v\n"
        "iverilog -g2012 -o sim/320/tb_sobel.vvp sim/320/tb_sobel.v sources_1/new/sobel_edge_filter.v\n"
        "for tb in tb_vga_640x320_display tb_sccb_config tb_frame_buffer_640x320 tb_edge tb_sobel; do\n"
        "    vvp sim/320/$tb.vvp\n"
        "done\n"
    )
    add_code_block(doc, run_cmds)
    doc.add_paragraph()

    add_tb_section(
        doc,
        "640/tb_vga_timing.v",
        "Verifies the VESA 640x480 @ 60 Hz timing generator "
        "(rtl/vga_timing.v) over a full frame. The testbench drives a "
        "25 MHz clock, releases reset, and runs for >416,800 cycles "
        "(one full 800 x 521 frame plus margin) while continuously "
        "self-checking the outputs against the expected sync windows.",
        "PASS: VGA timing OK (max_h=799 max_v=520)",
        [
            "h_count wraps 0..799 (max observed = 799).",
            "v_count wraps 0..520 (max observed = 520).",
            "hsync is LOW exactly when h in [656..751], HIGH otherwise.",
            "vsync is LOW exactly when v in [490..491], HIGH otherwise.",
            "active_video is HIGH iff h<640 and v<480.",
            "rd_addr is forced to 19'd0 outside the active region.",
        ],
    )

    add_tb_section(
        doc,
        "640/tb_sccb_master.v",
        "Verifies the bit-banged SCCB / 3-wire master "
        "(rtl/sccb_master.v) driving a 3-byte write transaction. Uses "
        "HALF_PER_CYCLES=4 to keep the simulation fast. Pull-ups on "
        "SDA / SCL emulate an idle bus (no slave attached), so all "
        "three ACK slots read back high (NAK).",
        "PASS: SCCB master: START+27 bits+STOP, done=1, scl_rises=28",
        [
            "START condition detected: SDA falls while SCL high.",
            "At least 27 SCL rising edges (one per bit slot).",
            "STOP condition detected: SDA rises while SCL high.",
            "done pulses exactly once per transaction.",
            "busy clears on the cycle after done.",
            "ack_id, ack_sub, ack_data sample the bus correctly.",
        ],
    )

    add_tb_section(
        doc,
        "640/tb_frame_buffer.v",
        "Verifies the dual-clock split frame buffer "
        "(rtl/frame_buffer.v) which stores Y3 per pixel and Cb2/Cr2 "
        "per pixel pair (YCbCr 4:2:2). Writes a known pattern to a "
        "small set of addresses and reads it back, checking both "
        "luma round-trip and chroma sharing across even/odd address "
        "pairs.",
        "PASS: frame_buffer luma + 4:2:2 chroma sharing OK",
        [
            "Luma writes at addr 0,1,2,3,1000 read back the exact value.",
            "Chroma write at even addr 0 is shared with odd addr 1 (same word).",
            "Chroma write at even addr 2 is shared with odd addr 3.",
            "wr_chroma_en correctly gates chroma writes so that odd-pixel writes do not corrupt the shared word.",
            "BRAM 1-cycle read latency is respected.",
        ],
    )

    add_tb_section(
        doc,
        "640/tb_filter_pipeline.v",
        "Verifies the 4-mode filter mux (rtl/filter_pipeline.v) which "
        "instantiates ycbcr_to_rgb444, line_buffer3, and filter_edge. "
        "Drives a constant gray luma + neutral chroma, switches "
        "sw_mode through each of the 4 codes, and checks the "
        "registered output. EDGE mode is also tested on a flat field "
        "(luma = 4 across a 3x640 region) to confirm the Sobel "
        "produces 0 (no false edges) when there is no gradient.",
        "PASS: filter_pipeline 4 modes OK (raw=979)",
        [
            "RAW mode: rgb444_out is non-zero (mid-gray decode).",
            "INVERT mode: rgb444_out == ~raw_sample.",
            "COLOR_ISO R: only the R nibble is non-zero.",
            "COLOR_ISO G: only the G nibble is non-zero.",
            "COLOR_ISO B: only the B nibble is non-zero.",
            "EDGE on flat field: rgb444_out == 12'h000 (mag = 0 < threshold).",
        ],
    )

    add_tb_section(
        doc,
        "320/tb_edge.v",
        "Existing legacy testbench for the simple 1D edge_unit "
        "(sim/edge_unit.v). Drives a sequence of brightness changes "
        "across the active-video signal and counts edge pulses on "
        "the output. Acts as a sanity check that the basic temporal "
        "edge detector produces non-zero output on luminance "
        "transitions.",
        "PASS: observed 4 edge pulses",
        [
            "At least 2 edge pulses observed on the brightness ramp 0->4->7->C->2->0.",
            "No false edges during the constant-brightness hold.",
            "Output drops to 0 when video_active is de-asserted.",
        ],
    )

    add_tb_section(
        doc,
        "320/tb_sobel.v",
        "Existing legacy testbench for the standalone Sobel filter "
        "(sources_1/new/sobel_edge_filter.v). Drives a 6x6 synthetic "
        "image with a vertical step edge (left half dark 12'h111, "
        "right half bright 12'hEEE) and counts edge pulses produced "
        "by the 3x3 Sobel kernel.",
        "PASS: Sobel produced 8 edge pulses",
        [
            "Sobel produces non-zero output along the vertical step edge.",
            "Edge magnitude exceeds threshold for the column transition.",
            "No edges produced in the uniform left/right halves.",
        ],
    )

    add_tb_section(
        doc,
        "320/tb_vga_640x320_display.v",
        "Verifies the 320-path VGA + upscale controller "
        "(sources_1/new/vga_640x320_display.v) over a full frame. "
        "Drives a 25 MHz pixel clock and a constant pixel_in = 12'hA5C. "
        "Runs 440,000 cycles (>1 full 800x525=420,000 cycle frame) "
        "and checks all outputs every clock.",
        "PASS: vga_640x320_display timing+output OK (max px=799 py=524)",
        [
            "h_cnt wraps 0..799 (max pixel_x observed = 799).",
            "v_cnt wraps 0..524 (max pixel_y observed = 524).",
            "hsync is LOW when h in [656..751], HIGH otherwise.",
            "vsync is LOW when v in [490..491], HIGH otherwise.",
            "vga_r/g/b equal pixel_in nibbles exactly when active is HIGH.",
            "vga_r/g/b are all 4'h0 when active is LOW (blanking).",
            "frame_addr stays in [0..76799] inside the active region.",
        ],
    )

    add_tb_section(
        doc,
        "320/tb_sccb_config.v",
        "Verifies the 320-path 8-register SCCB sequencer "
        "(sources_1/new/sccb_config.v). Drives a 25 MHz clock with "
        "open-drain pull-ups on sioc/siod (no slave attached). "
        "Counts STOP conditions (siod rises while sioc high after a "
        "START) and expects exactly 8 stops, one per register write.",
        "PASS: sccb_config sent 8 register writes (STOP conditions)",
        [
            "SCCB START detected: siod falls while sioc high.",
            "SCCB STOP detected: siod rises while sioc high (per SCCB spec).",
            "Exactly 8 STOP events observed (one per register in the ROM).",
            "All 8 transactions complete within the time budget "
            "(8 x ~6400 sys cycles + 25600 gap for reg_idx=1).",
        ],
    )

    add_tb_section(
        doc,
        "320/tb_frame_buffer_640x320.v",
        "Verifies the 320-path single-BRAM RGB444 frame buffer "
        "(sources_1/new/frame_buffer_640x320.v): 76,800 x 12-bit "
        "entries, dual-clock (same clock used here for simplicity). "
        "Writes known 12-bit values to 5 representative addresses "
        "and reads them back; also confirms the we=0 gate does not "
        "overwrite existing data.",
        "PASS: frame_buffer_640x320 R/W + we-gate OK",
        [
            "Write + read-back correct at addr 0 (12'hABC).",
            "Write + read-back correct at addr 1 (12'h123).",
            "Write + read-back correct at addr 319 - last pixel of row 0 (12'hFFF).",
            "Write + read-back correct at addr 320 - first pixel of row 1 (12'hDEF).",
            "Write + read-back correct at addr 76799 - last pixel in buffer (12'h555).",
            "we=0 gate verified: addr 0 retains 12'hABC after a we=0 write attempt.",
            "1-cycle synchronous read latency respected in all checks.",
        ],
    )

    # ---------------- Challenges ----------------
    add_heading(doc, "Challenge Faced", level=1)
    add_para(
        doc,
        "In this section, what challenges have been faced during this project.",
        italic=True,
    )
    challenges = [
        "OV7670 has finicky power-up timing - reset hold, post-reset "
        "wait, and per-register SCCB gap all need to be tuned, or the "
        "sensor either ignores writes or boots into a wrong format.",
        "BRAM is the hard wall on XC7A35T. Storing the full 640x480 "
        "frame in RGB565 will not fit, so the design had to commit to "
        "YCbCr 4:2:2 with aggressive bit-depth quantization (Y3, Cb2, "
        "Cr2) before any feature work could land.",
        "Two clock domains (24 MHz cam, 25 MHz VGA) plus the camera "
        "PCLK input make CDC easy to get wrong. We confine crossings "
        "to dual-port BRAM and a dedicated cdc_pulse_sync rather than "
        "letting them appear ad-hoc across the design.",
        "Color reproduction was the biggest tuning effort. Early "
        "versions had a green bias from rounding inside the chroma "
        "decoder and from bin thresholds that were not antisymmetric; "
        "fixing required choosing thresholds (-48, 0, +48) and offset "
        "tables that round-trip a neutral gray.",
        "The 320x240 and 640x480 variants needed different storage "
        "schemes: 320 fits comfortably in RGB444 with no math, while "
        "640 only fits as YCbCr 4:2:2. Keeping both code paths in "
        "sync during refactors was non-trivial.",
        "Sobel on a 3-bit luma is coarse; threshold tuning matters "
        "more than usual. Adding the dither bit on the read side "
        "(effectively Y4 to the filter) recovered a lot of detail.",
    ]
    for c in challenges:
        add_bullet(doc, c)
    doc.add_paragraph()

    # ---------------- AI Usage Declaration ----------------
    add_heading(doc, "AI Usage Declaration", level=1)
    add_para(
        doc,
        "Per the project rubric (pass/fail requirement), this section "
        "discloses any use of AI tools during the project.",
    )
    add_para(doc, "Tools used:", bold=True)
    add_bullet(
        doc,
        "Anthropic Claude (Claude Code CLI) - used to draft and "
        "iteratively refine the Verilog modules listed in this "
        "report (cam_capture, ycbcr_to_rgb444, filter_pipeline, "
        "line_buffer3, filter_edge, vga_timing, sccb_master, "
        "frame_buffer, top.v) and the testbenches in the sim/ "
        "directory. All generated code was inspected, edited, and "
        "validated on hardware (Basys 3 + OV7670) and in simulation "
        "(Icarus Verilog) by the team.",
    )
    add_bullet(
        doc,
        "Anthropic Claude - used to help draft this report itself "
        "(structural outline + paragraph drafts). Final wording, "
        "design decisions, and challenge entries reflect the team's "
        "actual experience.",
    )
    add_para(doc, "Specific applications:", bold=True)
    add_bullet(
        doc,
        "Code generation: SCCB FSM scaffolding, BT.601 luma multiply, "
        "antisymmetric chroma quantization bins, 3x3 line buffer "
        "sliding window, VGA 640x480 timing constants.",
    )
    add_bullet(
        doc,
        "Debugging assistance: explaining iverilog scheduling races "
        "in the testbench, narrowing the green-bias bug in the "
        "chroma decoder, locating the byte-pairing reset point in "
        "cam_capture for the 320 -> 640 port.",
    )
    add_bullet(
        doc,
        "Documentation: drafting module description blocks and the "
        "Q/A entries in the Design Decision section.",
    )
    add_para(doc, "Not done by AI:", bold=True)
    add_bullet(
        doc,
        "Hardware bring-up, oscilloscope / scope-on-LED debug, pin "
        "mapping verification, on-board demonstration tuning, and "
        "the final architectural decisions (YCbCr 4:2:2 storage, "
        "Y3+Cb2+Cr2 bit depth, dither scheme, threshold values).",
    )

    doc.save(OUT_PATH)
    print(f"Wrote {OUT_PATH}")


if __name__ == "__main__":
    build()
