#!/usr/bin/env python3
"""
Build demo_ov7670.docx following the demo PDF structure.
Run from any directory: python interactive_doc/build_doc.py
Output: interactive_doc/demo_ov7670.docx (overwrites existing)
"""
import pathlib
import sys

try:
    from docx import Document
    from docx.shared import Pt, RGBColor, Inches
    from docx.oxml.ns import qn
    from docx.oxml import OxmlElement
except ImportError:
    print("Install python-docx first:  pip install python-docx")
    sys.exit(1)

ROOT = pathlib.Path(__file__).resolve().parent.parent
RTL  = ROOT / "rtl"
SRC  = ROOT / "sources_1" / "new"
OUT  = pathlib.Path(__file__).resolve().parent / "demo_ov7670.docx"


# ── helpers ──────────────────────────────────────────────────────────────────

def read_v(path: pathlib.Path) -> str:
    if path.exists():
        return path.read_text(encoding="utf-8", errors="replace")
    return f"[Source file not found: {path}]"


doc = Document()

# Narrow margins so code fits
for section in doc.sections:
    section.left_margin   = Inches(1.0)
    section.right_margin  = Inches(1.0)
    section.top_margin    = Inches(1.0)
    section.bottom_margin = Inches(1.0)


def h1(text: str):
    doc.add_heading(text, level=1)


def h2(text: str):
    doc.add_heading(text, level=2)


def para(text: str = "", bold: bool = False):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.bold = bold
    return p


def bullet(text: str):
    p = doc.add_paragraph(style="List Bullet")
    p.add_run(text)


def shade_cell(cell, hex_fill: str = "D9D9D9"):
    """Light-gray background for a table cell."""
    tc   = cell._tc
    tcPr = tc.get_or_add_tcPr()
    shd  = OxmlElement("w:shd")
    shd.set(qn("w:val"),   "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"),  hex_fill)
    tcPr.append(shd)


def code_block(source: str):
    """Single-cell table, Courier New 8pt, light-gray background."""
    tbl  = doc.add_table(rows=1, cols=1)
    tbl.style = "Table Grid"
    cell = tbl.cell(0, 0)
    shade_cell(cell, "F2F2F2")

    first = True
    for line in source.splitlines():
        if first:
            p = cell.paragraphs[0]
            first = False
        else:
            p = cell.add_paragraph()
        run = p.add_run(line)
        run.font.name = "Courier New"
        run.font.size = Pt(7.5)
    doc.add_paragraph()   # spacing after code block


def qa(question: str, answer: str):
    """Q&A paragraph in demo-PDF style."""
    p = doc.add_paragraph()
    p.add_run(f"- {question}").bold = False
    doc.add_paragraph()
    ans_p = doc.add_paragraph()
    ans_p.style = doc.styles["Normal"]
    run = ans_p.add_run(f"\t○ Answer : {answer}")
    run.font.size = Pt(11)
    doc.add_paragraph()


# ═════════════════════════════════════════════════════════════════════════════
# 1. GROUP MEMBER
# ═════════════════════════════════════════════════════════════════════════════
h1("Group Member")
para("Group name : ต้นน้ำทรงพลัง")
doc.add_paragraph()

members_tbl = doc.add_table(rows=4, cols=2)
members_tbl.style = "Table Grid"

hdr = members_tbl.rows[0].cells
hdr[0].text = "Name"
hdr[1].text = "Student Number"
for cell in hdr:
    for run in cell.paragraphs[0].runs:
        run.bold = True

members = [
    ("Chanasuek Chaiyasorn",  "6731309021"),
    ("Saranpat Pewsouykam",   "6730489021"),
    ("Sarus Suanploy",        "6730493521"),
]
for i, (name, sid) in enumerate(members):
    row = members_tbl.rows[i + 1].cells
    row[0].text = name
    row[1].text = sid

doc.add_paragraph()

# ═════════════════════════════════════════════════════════════════════════════
# 2. OVERALL DESIGN BLOCK DIAGRAM
# ═════════════════════════════════════════════════════════════════════════════
h1("Overall Design Block Diagram")

para("Real-time 640×480 video pipeline on Basys 3 + OV7670. Pixels stream from "
     "the camera at 24 MHz, get quantized to YCbCr 4:2:2 (Y3 + Cb2/Cr2) for "
     "BRAM storage, and are read back at 25 MHz for VGA output through a "
     "filter pipeline.")
doc.add_paragraph()

DIAGRAM = """\
  clk_100 (Basys3 100 MHz crystal)
      |
      v
  clk_wiz_main  (MMCM)  ──── clk_25  ──── VGA pixel + main logic
                         ──── clk_24  ──── cam XCLK → OV7670

  OV7670 sensor
      |  RGB565 (2 bytes/pixel) over D[7:0], PCLK, HREF, VSYNC
      v
  cam_capture          RGB565 → YCbCr 4:2:2  (Y3, Cb2, Cr2)
      |  write @ cam_pclk (~24 MHz)
      v
  frame_buffer         split BRAM:
                         luma_mem  307,200 × 3 b  (~30 BRAM36)
                         chroma_mem 153,600 × 4 b  (~20 BRAM36)
      |  read @ clk_25
      v
  filter_pipeline      SW[1:0] selects mode:
                         00 = RAW (decoded YCbCr → RGB444)
                         01 = INVERT (bitwise NOT of RGB444)
                         10 = COLOR_ISO (gate channels by SW[3:2])
                         11 = EDGE (3×3 Sobel on Y3, threshold SW[7:4])
      |  (EDGE mode uses line_buffer3 + filter_edge)
      v
  ycbcr_to_rgb444      Y3 + dither → Y4; LUT offsets → clamp → 12-bit RGB444
      |
      v
  vga_timing  ──► HSYNC / VSYNC / RGB444 to VGA connector

  ─ Boot path ──────────────────────────────────────────────────────────
  cam_config  (77-reg SCCB ROM)  →  sccb_master  →  SIOC/SIOD  →  OV7670
"""
code_block(DIAGRAM)

# ═════════════════════════════════════════════════════════════════════════════
# 3. DEMO VIDEO LINK
# ═════════════════════════════════════════════════════════════════════════════
h1("Demo Video")
para("Demo recording (Google Drive):")
para("[Insert Google Drive / YouTube link here]")
doc.add_paragraph()

# ═════════════════════════════════════════════════════════════════════════════
# 3b. SUMMARY — FILTER SELECTION
# ═════════════════════════════════════════════════════════════════════════════
h1("Summary - Filter Selection")
para("Per the project rubric (3 distinct hardware-based filters, togglable in "
     "real-time via Basys 3 slide switches), this group implemented the following:")
doc.add_paragraph()
bullet("Color Inversion (Negative) — bitwise NOT of the decoded RGB444 output. "
       "Selected via SW[1:0] = 2'b01.")
bullet("Color Channel Isolation — pass-through of a single R / G / B channel "
       "chosen by SW[3:2]. Selected via SW[1:0] = 2'b10.")
bullet("Sobel Edge Detection — 3x3 convolution on luma (Y3) using a sliding line "
       "buffer, with threshold tunable via SW[7:4]. Selected via SW[1:0] = 2'b11.")
doc.add_paragraph()
para("SW[1:0] = 2'b00 displays the raw decoded video stream "
     "(YCbCr 4:2:2 -> RGB444 with 2x2 Bayer dither).")
doc.add_paragraph()

# ═════════════════════════════════════════════════════════════════════════════
# 4. DESIGN DECISION
# ═════════════════════════════════════════════════════════════════════════════
h1("Design Decision")

# 4.1
h2("1. Module Architecture")
qa("Why did you structure your design this way?",
   "Each functional block lives in its own file (cam_capture, frame_buffer, "
   "filter_pipeline, ycbcr_to_rgb444, sccb_master, vga_timing). "
   "Clock-domain boundaries (cam_pclk vs clk_25) are isolated to specific "
   "modules so that timing constraints stay simple. The top-level only wires "
   "everything together and owns the reset-and-config FSM.")
qa("What are the advantages of using this approach?",
   "Modularity makes it easy to swap implementations (e.g. RGB444 vs YCbCr "
   "4:2:2 storage), debug each stage in isolation with a dedicated testbench, "
   "and reason about clock-domain crossings since they are confined to "
   "frame_buffer and cdc_pulse_sync.")

# 4.2
h2("2. Communication Protocols")
qa("Why did you choose this specific protocol for communication?",
   "SCCB (Serial Camera Control Bus, OmniVision-defined, ~95% I2C-compatible) "
   "is the only configuration interface OV7670 exposes, so it is mandatory for "
   "setting RGB565 output, resolution, gain, and AWB. The pixel data path "
   "itself is a synchronous parallel bus (PCLK / HREF / VSYNC / D[7:0]).")
qa("How does this protocol suit your design requirements?",
   "Configuration is one-shot and slow (~100 kHz SCCB), so bit-banging it from "
   "clk_25 is cheap and never gets in the way of the high-throughput pixel bus. "
   "The parallel bus on the data side gives one byte per PCLK with no protocol "
   "overhead, which matches the 25 MHz fill rate VGA needs.")

# 4.3
h2("3. Clock and Data Transfer Rate")
qa("Why did you select this specific clock frequency?",
   "Two clocks are derived by the MMCM from the 100 MHz board crystal: "
   "25.000 MHz for VGA pixel + main logic (matches VESA 640×480@60 Hz timing) "
   "and 24.000 MHz for the camera XCLK (OV7670 datasheet typical). The frame "
   "buffer is dual-clock (write @ 24 MHz, read @ 25 MHz) so each domain runs "
   "at its native rate.")
qa("How does the data rate impact system performance?",
   "VGA at 25 MHz consumes one pixel per cycle = 60 frames/sec. OV7670 streams "
   "~30 fps at 24 MHz XCLK. Because the frame buffer decouples producer and "
   "consumer, brief rate differences are absorbed without tearing. Heavy math "
   "(BT.601 luma multiply, Sobel) sits on the read side at 25 MHz, leaving the "
   "write side light.")
qa("Did you consider constraints such as FPGA timing, external device "
   "compatibility, or noise margins?",
   "Yes. Both 24 MHz and 25 MHz come from the same MMCM VCO (1200 MHz) so "
   "they share a known phase relationship; CDC is still treated explicitly via "
   "a dual-port BRAM and cdc_pulse_sync for VSYNC. SCCB is held at ~100 kHz "
   "to stay well within OV7670 spec and to tolerate breadboard pull-up "
   "tolerances.")

# 4.4
h2("4. Resource Utilization")
qa("How does your design balance resource usage (LUTs, FFs, BRAMs) and "
   "performance?",
   "The 640×480 frame would not fit in BRAM at full RGB565 (16 bpp → 4.9 Mb), "
   "so the design quantizes to YCbCr 4:2:2 with Y3 + Cb2 + Cr2 = 5 bits/"
   "pixel = 1.54 Mb total. Luma uses ~30 BRAM36 tiles, chroma ~20, hitting "
   "full utilization on XC7A35T. LUTs are spent on the BT.601 multiply "
   "(write side) and the Sobel kernel + threshold (read side). FFs hold "
   "pipeline registers and the SCCB FSM.")
qa("Why did you optimize certain parts of the design?",
   "Hot paths are the per-pixel converter (write side) and the Sobel + line "
   "buffer (read side). Y is computed combinationally from RGB, then registered "
   "before BRAM. The Cb/Cr 4-bin quantizer keeps thresholds antisymmetric "
   "(-48, 0, +48) so a neutral pixel round-trips back to neutral. The decoder "
   "uses small case-statement LUTs for r_off/b_off/g_off, sums and clamps to "
   "RGB444 — no DSPs needed on the read side.")

# ═════════════════════════════════════════════════════════════════════════════
# 5. IMPLEMENTATION DETAIL
# ═════════════════════════════════════════════════════════════════════════════
h1("Implementation Detail")

MODULES = [
    ("top", RTL / "top.v",
     "Top-level wrapper. Instantiates the MMCM (clk_25 + clk_24), debouncer, "
     "sccb_master + cam_config, cam_capture, frame_buffer, filter_pipeline "
     "(which embeds line_buffer3, filter_edge, and ycbcr_to_rgb444), and "
     "vga_timing. Owns the reset hold / camera power-up sequence and routes "
     "SW[15:0] into per-module mode and threshold inputs. LD[15] indicates "
     "SCCB config done; LD[14] toggles every camera VSYNC; LD[13:8] show "
     "reg_writes_done count."),

    ("clk_wiz_main", RTL / "clk_wiz_main.v",
     "Wraps an MMCME2_BASE primitive (synthesis) or behavioural clock "
     "generators (simulation). Produces clk_25 (VGA pixel) and clk_24 "
     "(camera XCLK) from a single 100 MHz board input. VCO = 100×12 / 1 = "
     "1200 MHz; CLKOUT0 / 48 = 25 MHz, CLKOUT1 / 50 = 24 MHz. Outputs "
     "LOCKED for downstream reset."),

    ("cam_config", RTL / "cam_config.v",
     "Boot-time SCCB sequencer. Drives cam_rst_n through a hold + release "
     "schedule, then walks a 77-entry register-write ROM (COM7 = RGB output, "
     "COM15 = RGB565 full range, plus AWB / gamma / scaling). Issues one "
     "16-bit {reg, value} command at a time to sccb_master and waits for "
     "done before advancing. Also handles SW[8] camera color-bar test pattern."),

    ("sccb_master", RTL / "sccb_master.v",
     "Bit-banged SCCB / 3-wire master. Generates START, byte transfers "
     "(device address 0x42 + W, register address, data) and STOP on SIOC / "
     "SIOD. The 9th bit of each byte is the SCCB don't-care slot (master "
     "releases SDA). ACK is sampled mid-SCL-high on each DC slot. Runs at "
     "~49 kHz SCL (HALF_PER_CYCLES=128 at 25 MHz), well within OV7670 "
     "datasheet limit of 400 kHz."),

    ("cam_capture", RTL / "cam_capture.v",
     "Pixel ingest in cam_pclk domain. Captures RGB565 in two halves on "
     "consecutive HREF byte pulses, bit-replicates R5/G6/B5 to 8-bit "
     "channels, computes BT.601 luma Y8 = (77R + 150G + 29B) >> 8, "
     "truncates to Y3 = Y8[7:5], and quantizes diff_b = B-Y and diff_r = "
     "R-Y into 4 bins each (Cb2, Cr2). Writes Y per pixel and Cb/Cr only "
     "on even columns (4:2:2 subsampling). byte_sel resets on HREF fall to "
     "prevent byte-swap drift between lines. SW[9] injects a synthetic "
     "R/G/B vertical bar test pattern."),

    ("frame_buffer", RTL / "frame_buffer.v",
     "Split dual-clock BRAM storage for YCbCr 4:2:2. luma_mem holds "
     "307,200 entries × 3 bits; chroma_mem holds 153,600 entries × 4 bits "
     "(Cb2+Cr2 shared across each horizontal pair at address >> 1). Writes "
     "are clocked by cam_pclk; reads by clk_25. The dual-port BRAM "
     "primitives handle the clock-domain crossing at the byte level without "
     "a FIFO."),

    ("ycbcr_to_rgb444", RTL / "ycbcr_to_rgb444.v",
     "Read-side decoder. Appends a Bayer 2×2 dither bit (h_pos XOR v_pos) "
     "to the 3-bit luma to get Y4 (range 0..15). Looks up antisymmetric "
     "offsets for R (from Cr), B (from Cb), and G (from both) using 4-entry "
     "case-statement LUTs. Sums offset + Y4, clamps to 0..15, and outputs "
     "12-bit RGB444. Bin-1 (mild deficit) and bin-2 (mild positive) are "
     "antisymmetric so a neutral gray pixel round-trips correctly."),

    ("filter_pipeline", RTL / "filter_pipeline.v",
     "Read-side mode mux. SW[1:0] selects: 00=RAW (decoded YCbCr→RGB444), "
     "01=INVERT (XOR 0xFFF), 10=COLOR_ISO (gate channels by SW[3:2]), "
     "11=EDGE (Sobel on luma → white-on-black mask). All modes have equal "
     "2-cycle latency so no pipeline mis-alignment occurs when switching "
     "modes. Instantiates ycbcr_to_rgb444, line_buffer3, and filter_edge."),

    ("line_buffer3", RTL / "line_buffer3.v",
     "Three-row sliding window for 2D filters. Shifts incoming Y3 samples "
     "through three distributed-RAM line stores so that filter_edge sees a "
     "3×3 neighbourhood per cycle. The current pixel (bottom-right) is "
     "forwarded directly to avoid read-before-write on the bottom buffer."),

    ("filter_edge", RTL / "filter_edge.v",
     "Sobel edge detector on 3-bit luma. Computes Gx (horizontal) and Gy "
     "(vertical) 3×3 gradient sums, approximates magnitude as |Gx| + |Gy| "
     "(L1 norm, avoids square-root). Thresholds against SW[7:4] to produce "
     "a binary edge mask. Frame-edge pixels are forced black to suppress "
     "artefacts from the out-of-bounds 3×3 window."),

    ("vga_timing", RTL / "vga_timing.v",
     "VESA 640×480 @ 60 Hz timing generator. H_TOTAL=800 (active=640, "
     "FP=16, sync=96, BP=48); V_TOTAL=525 (active=480, FP=10, sync=2, "
     "BP=33). Produces hsync/vsync (active-low), active_video, and "
     "fetch_active (extends 3 cycles past active region for pre-fetch). "
     "rd_addr is computed combinationally with vertical flip (line_base "
     "counts down from row 479→0) and horizontal mirror "
     "(h_scaled = eff_h × 998 >> 10, mirror_x = VALID_COLS-1 − h_scaled)."),

    ("debouncer", RTL / "debouncer.v",
     "Generic W-bit counter-based debouncer with a per-bit two-flop "
     "synchronizer. With N=20 stability counter, an input must be stable "
     "for 2²⁰ clocks (~42 ms at 25 MHz) before the output flips. Used for "
     "all 16 switches and BTNC."),

    ("cdc_pulse_sync", RTL / "cdc_pulse_sync.v",
     "Single-pulse CDC synchronizer. Toggle-flop in the source domain "
     "(cam_pclk), three-FF synchronizer + edge-detect in the destination "
     "domain (clk_25). Flops are marked (* ASYNC_REG = \"TRUE\" *) so "
     "Vivado places them in adjacent flip-flops for minimum metastability "
     "MTBF. Used to bring the camera VSYNC pulse into clk_25 for the "
     "frame-rate LED toggle."),
]

for mod_name, mod_path, mod_desc in MODULES:
    h2(f"Module : {mod_name}")
    para("Module code:")
    code_block(read_v(mod_path))
    para("Module Description:")
    para(mod_desc)
    doc.add_paragraph()

# ═════════════════════════════════════════════════════════════════════════════
# 6. SIMULATION & TESTBENCHES
# ═════════════════════════════════════════════════════════════════════════════
h1("Simulation & Testbenches")

para("All major modules have dedicated cocotb 2.x Python testbenches under "
     "tests/640/ (for the rtl/ path). Testbenches compile and simulate with "
     "Icarus Verilog via python run_tests.py.")
para("How to run all testbenches:")
code_block("cd tests/640\npython run_tests.py          # all six targets\npython run_tests.py vga_timing filter_pipeline   # subset")
doc.add_paragraph()

TESTBENCHES = [
    ("test_vga_timing",
     "Verifies the VESA 640×480 @60 Hz timing generator (rtl/vga_timing.v). "
     "Drives a 25 MHz clock and runs for >1 full frame (>420,000 cycles). "
     "Checks h_count wraps 0..799, v_count wraps 0..524 (V_TOTAL=525), "
     "hsync LOW for h in [656..751], vsync LOW for v in [490..491], "
     "active_video HIGH iff h<640 and v<480, and rd_addr=0 outside active region.",
     ["h_count wraps 0..799; max observed = 799.",
      "v_count wraps 0..524 (V_TOTAL=525); max observed = 524.",
      "hsync is LOW exactly when h ∈ [656..751], HIGH otherwise.",
      "vsync is LOW exactly when v ∈ [490..491], HIGH otherwise.",
      "fetch_active covers active region plus 3-cycle prefetch window.",
      "rd_addr forced to 0 when !fetch_active."],
     "** TESTS=4 PASS=4 FAIL=0 SKIP=0 **"),

    ("test_sccb_master",
     "Verifies the bit-banged SCCB master (rtl/sccb_master.v). Compiled "
     "with HALF_PER_CYCLES=4 to keep simulation to ~250 cycles per "
     "transaction instead of ~7900. Open-drain bus with no slave attached "
     "so all three ACK slots read back 1 (NAK).",
     ["Idle state: busy=0, done=0 after reset.",
      "start pulse → busy rises; done pulses exactly once; busy falls next cycle.",
      "done stays high for exactly one clock cycle.",
      "Second start during busy is ignored — only one done pulse results.",
      "rst mid-transaction immediately clears busy and done.",
      "ack_id/ack_sub/ack_data = 1 with no slave on the bus."],
     "** TESTS=6 PASS=6 FAIL=0 SKIP=0 **"),

    ("test_frame_buffer",
     "Verifies the dual-clock split frame buffer (rtl/frame_buffer.v) "
     "storing Y3 per pixel and Cb2/Cr2 per pixel pair (YCbCr 4:2:2).",
     ["Luma write+readback correct at addresses 0, 1, 2, 3, 1000.",
      "Chroma write at even addr 0 is shared with odd addr 1 (same chroma word).",
      "wr_chroma_en=0 on odd columns does not corrupt the shared chroma word.",
      "BRAM 1-cycle read latency respected in all checks."],
     "** TESTS=3 PASS=3 FAIL=0 SKIP=0 **"),

    ("test_filter_pipeline",
     "Verifies the 4-mode filter mux (rtl/filter_pipeline.v), which "
     "instantiates ycbcr_to_rgb444, line_buffer3, and filter_edge.",
     ["RAW mode: rgb444_out is non-zero for mid-gray luma + neutral chroma.",
      "INVERT mode: rgb444_out == ~raw_sample & 0xFFF.",
      "COLOR_ISO R: only the R nibble is non-zero.",
      "COLOR_ISO G: only the G nibble is non-zero.",
      "COLOR_ISO B: only the B nibble is non-zero.",
      "EDGE on flat field (luma=4 across 3×640): rgb444_out == 0x000 (no gradient)."],
     "** TESTS=6 PASS=6 FAIL=0 SKIP=0 **"),

    ("test_cam_capture",
     "Verifies the OV7670 pixel ingest (rtl/cam_capture.v).",
     ["First PIXEL_SKIP=16 pixels per HREF → wr_en=0 (OV7670 startup glitch).",
      "Pure-red RGB565 (0xF800) → wr_luma=2, wr_chroma non-zero.",
      "vsync pulse asserts vsync_pulse for one cycle, clears wr_en.",
      "After second HREF line, wr_addr ≥ 640 (row_base advanced).",
      "wr_chroma_en alternates 1,0,1,0... (4:2:2 even-column write)."],
     "** TESTS=5 PASS=5 FAIL=0 SKIP=0 **"),

    ("test_ycbcr_to_rgb444",
     "Verifies the combinational YCbCr decoder (rtl/ycbcr_to_rgb444.v). "
     "No clock needed; drive inputs, await 1 ns propagation, check output.",
     ["Six known (in_y, in_cb, in_cr, h_pos, v_pos) → out_rgb444 match reference model.",
      "Large positive offset clamps to 15, not wrap (y4=14 + r_off=+3 → 15).",
      "Large negative offset clamps to 0, not underflow (y4=0 + r_off=-3 → 0).",
      "Flipping h_pos changes dither, shifts y4 by 1, changes all channels.",
      "All 32 (in_cb, in_cr, h_pos) combinations at mid-luma produce defined output."],
     "** TESTS=5 PASS=5 FAIL=0 SKIP=0 **"),
]

for tb_name, tb_desc, tb_checks, tb_result in TESTBENCHES:
    h2(f"Testbench : {tb_name}")
    para("Module under test + what is verified:")
    para(tb_desc)
    para("Specific checks:")
    for chk in tb_checks:
        bullet(chk)
    para("Testbench source: tests/640/" + tb_name + ".py")
    para("Simulation result (python run_tests.py " + tb_name.replace("test_", "") + "):")
    code_block(tb_result)
    doc.add_paragraph()

# ── cocotb 320-path testbenches ──────────────────────────────────────────────
h2("cocotb Testbenches — 320-path (sources_1/new/)")
para("Six Python testbenches under tests/320/ cover the baseline 320×240 pipeline. "
     "Run with: cd tests/320 && python run_tests.py")
doc.add_paragraph()

TESTBENCHES_320 = [
    ("test_camera_capture",
     "Verifies camera_capture_640x320 (sources_1/new/camera_capture_640x320.v). "
     "Drives PCLK / HREF / VSYNC and checks byte-pair assembly, pixel-skip, "
     "line_cnt even/odd gating, and byte_sel reset on HREF fall.",
     ["First PIXEL_SKIP bytes per HREF: write_en=0.",
      "Full pixel pair on even line produces write_en=1 with correct RGB444.",
      "byte_sel resets to 0 on HREF falling edge (prevents byte-swap drift).",
      "Odd line_cnt (1,3,...): write_en=0 — only even lines are kept.",
      "Even line after odd: write_en=1 (downsampler resumes)."],
     "** TESTS=5 PASS=5 FAIL=0 SKIP=0 **"),

    ("test_vga_display",
     "Verifies vga_640x320_display (sources_1/new/vga_640x320_display.v). "
     "Checks VGA counter bounds, sync polarity, and horizontal upscale formula.",
     ["h_cnt wraps 0..799 (HTOTAL=800).",
      "v_cnt wraps 0..524 (VTOTAL=525).",
      "hsync LOW in h=[656..751]; vsync LOW in v=[490..491].",
      "active_d HIGH iff h<640 and v<480.",
      "frame_addr upscale: img_x=(h_cnt*496)>>10, img_y=v_cnt>>1."],
     "** TESTS=5 PASS=5 FAIL=0 SKIP=0 **"),

    ("test_frame_buffer",
     "Verifies frame_buffer_640x320 (sources_1/new/frame_buffer_640x320.v). "
     "76,800 × 12-bit dual-clock BRAM: write @ pclk, read @ 25 MHz.",
     ["Write+readback correct at address 0, 1, 5, 100.",
      "BRAM 1-cycle read latency respected in all checks."],
     "** TESTS=3 PASS=3 FAIL=0 SKIP=0 **"),

    ("test_sccb_config",
     "Verifies sccb_config (sources_1/new/sccb_config.v). "
     "8-register minimal OV7670 init sequence over a bit-banged SCCB bus.",
     ["Idle: busy=0 before start.",
      "start pulse → busy rises within 1 cycle.",
      "done pulses once per 3-byte transaction.",
      "All 8 register writes complete; done_all asserts after last write."],
     "** TESTS=4 PASS=4 FAIL=0 SKIP=0 **"),

    ("test_line_buffer3",
     "Verifies line_buffer3 (sources_1/new/line_buffer3.v). "
     "Three-row distributed-RAM sliding window; WIDTH=8 for fast simulation.",
     ["After 3 full lines loaded: all 9 window positions hold expected values.",
      "Top-left corner of window updates correctly on each new pixel.",
      "Middle row values persist while bottom row advances.",
      "Forward path: bot_r equals current pix_in (no read-before-write stale).",
      "Wrap: window shifts correctly across a full line boundary."],
     "** TESTS=5 PASS=5 FAIL=0 SKIP=0 **"),

    ("test_filter_edge",
     "Verifies filter_edge (sources_1/new/filter_edge.v). "
     "3×3 Sobel on 3-bit luma with L1 magnitude and threshold from sw_threshold.",
     ["Flat field (all 9 pixels identical): output=0 (no gradient).",
      "Vertical step edge: Gx large, output > threshold → edge detected.",
      "Horizontal step edge: Gy large, output > threshold → edge detected.",
      "Diagonal: both Gx and Gy contribute.",
      "Frame-edge pixels (h_edge or v_edge): output forced to 0.",
      "Threshold sweep: lower threshold finds more edges, higher threshold fewer.",
      "Strong edge with threshold=0: output always non-zero."],
     "** TESTS=7 PASS=7 FAIL=0 SKIP=0 **"),
]

for tb_name, tb_desc, tb_checks, tb_result in TESTBENCHES_320:
    h2(f"Testbench : {tb_name}")
    para("Module under test + what is verified:")
    para(tb_desc)
    para("Specific checks:")
    for chk in tb_checks:
        bullet(chk)
    para("Testbench source: tests/320/" + tb_name + ".py")
    para("Simulation result (python run_tests.py " + tb_name.replace("test_", "") + "):")
    code_block(tb_result)
    doc.add_paragraph()

# ── Legacy Verilog testbenches (sim/) ────────────────────────────────────────
h2("Legacy Verilog Testbenches (sim/)")
para("Pre-cocotb Verilog testbenches compiled and run directly with iverilog + vvp. "
     "All pass under iverilog -g2012. VCD waveforms viewable in GTKWave.")
para("How to run:")
code_block(
    "# from repo root\n"
    "iverilog -g2012 -o sim/tb_vga_timing.vvp sim/tb_vga_timing.v rtl/vga_timing.v\n"
    "iverilog -g2012 -o sim/tb_sccb_master.vvp sim/tb_sccb_master.v rtl/sccb_master.v\n"
    "iverilog -g2012 -o sim/tb_frame_buffer.vvp sim/tb_frame_buffer.v rtl/frame_buffer.v\n"
    "iverilog -g2012 -o sim/tb_filter_pipeline.vvp sim/tb_filter_pipeline.v \\\n"
    "    rtl/filter_pipeline.v rtl/ycbcr_to_rgb444.v rtl/line_buffer3.v rtl/filter_edge.v\n"
    "for tb in tb_vga_timing tb_sccb_master tb_frame_buffer tb_filter_pipeline; do\n"
    "    vvp sim/$tb.vvp\n"
    "done"
)
doc.add_paragraph()

LEGACY_TBS = [
    ("tb_vga_timing",
     "Verifies VGA 640x480 @60 Hz timing (rtl/vga_timing.v) over one full frame "
     "(800x525 = 420,000 cycles). Self-checking: asserts hsync LOW in h=[656..751], "
     "vsync LOW in v=[490..491], active_video HIGH iff h<640 && v<480, "
     "rd_addr=0 outside active region.",
     ["h_count wraps 0..799 (max observed = 799).",
      "v_count wraps 0..524 (V_TOTAL=525; max observed = 524).",
      "hsync is LOW exactly when h in [656..751], HIGH otherwise.",
      "vsync is LOW exactly when v in [490..491], HIGH otherwise.",
      "active_video HIGH iff h<640 and v<480.",
      "rd_addr forced to 19'd0 outside active region."],
     "PASS: VGA timing OK (max_h=799 max_v=524)"),

    ("tb_sccb_master",
     "Verifies the bit-banged SCCB master (rtl/sccb_master.v), compiled with "
     "HALF_PER_CYCLES=4 for fast simulation. Pull-ups on SDA/SCL emulate an idle "
     "bus (no slave). All three ACK slots read back 1 (NAK).",
     ["START condition detected: SDA falls while SCL high.",
      "At least 27 SCL rising edges (one per bit slot).",
      "STOP condition detected: SDA rises while SCL high.",
      "done pulses exactly once per transaction.",
      "busy clears on the cycle after done.",
      "ack_id, ack_sub, ack_data = 1 (no slave attached)."],
     "PASS: SCCB master: START+27 bits+STOP, done=1, scl_rises=28"),

    ("tb_frame_buffer",
     "Verifies the dual-clock split BRAM (rtl/frame_buffer.v). Writes known luma "
     "and chroma values to addresses 0/1/2/3/1000 and reads them back, checking "
     "both luma round-trip and 4:2:2 chroma sharing across even/odd pairs.",
     ["Luma writes at addr 0,1,2,3,1000 read back the exact value.",
      "Chroma write at even addr 0 is shared with odd addr 1 (same chroma word).",
      "wr_chroma_en=0 on odd column does not corrupt the shared chroma word.",
      "BRAM 1-cycle read latency respected."],
     "PASS: frame_buffer luma + 4:2:2 chroma sharing OK"),

    ("tb_filter_pipeline",
     "Verifies the 4-mode filter mux (rtl/filter_pipeline.v). Drives constant "
     "gray luma + neutral chroma, cycles sw_mode through all 4 codes, and checks "
     "registered output. EDGE on flat field must yield 12'h000.",
     ["RAW mode: rgb444_out is non-zero (mid-gray decode).",
      "INVERT mode: rgb444_out == ~raw_sample.",
      "COLOR_ISO R: only the R nibble is non-zero.",
      "COLOR_ISO G: only the G nibble is non-zero.",
      "COLOR_ISO B: only the B nibble is non-zero.",
      "EDGE on flat field (constant luma): rgb444_out == 12'h000."],
     "PASS: filter_pipeline 4 modes OK (raw=979)"),
]

for tb_name, tb_desc, tb_checks, tb_result in LEGACY_TBS:
    h2(f"Testbench : {tb_name}")
    para("Module under test + what is verified:")
    para(tb_desc)
    para("Specific checks:")
    for chk in tb_checks:
        bullet(chk)
    para("Testbench source: sim/" + tb_name + ".v")
    para("Simulation result (iverilog -g2012 + vvp):")
    code_block(tb_result)
    doc.add_paragraph()

# ═════════════════════════════════════════════════════════════════════════════
# 7. CHALLENGE FACED
# ═════════════════════════════════════════════════════════════════════════════
h1("Challenge Faced")

challenges = [
    ("OV7670 finicky power-up timing",
     "Reset hold, post-reset wait, and per-register SCCB gap all need to be "
     "tuned precisely, or the sensor either ignores writes or boots into a "
     "wrong output format (e.g. YUV instead of RGB565)."),
    ("BRAM is the hard wall on XC7A35T",
     "Storing the full 640×480 frame in RGB565 does not fit (4.9 Mb > 1.8 Mb "
     "on-chip). The design had to commit to YCbCr 4:2:2 with aggressive "
     "bit-depth quantization (Y3, Cb2, Cr2 = 5 bits/pixel) before any "
     "feature work could land."),
    ("Two clock domains + non-clock-capable PCLK pin",
     "cam_pclk arrives on A16 (not a clock-capable input on Basys 3), so "
     "CLOCK_DEDICATED_ROUTE FALSE is required in the XDC. CDC crossings are "
     "confined to dual-port BRAM and a dedicated cdc_pulse_sync rather than "
     "letting them appear ad-hoc across the design."),
    ("Color reproduction tuning",
     "Early versions had a green bias caused by rounding inside the chroma "
     "decoder and by bin thresholds that were not antisymmetric. Fixing "
     "required choosing thresholds (-48, 0, +48) and LUT offset tables that "
     "round-trip a neutral gray pixel correctly."),
    ("VGA pipeline alignment",
     "Getting the 3-cycle latency (BRAM + filter_pipeline) to align exactly "
     "with active_video required a 3-cycle shift register (active_pipe) and "
     "a 3-cycle pre-fetch window (h_count 797-799) in vga_timing. Earlier "
     "builds had a 4-pixel rightward content shift from an over-pipelined "
     "rd_addr register."),
    ("Sobel on 3-bit luma is coarse",
     "With only 8 luma levels, threshold tuning matters more than usual. "
     "The Bayer dither on the decode side (effectively Y4 instead of Y3 "
     "to the filter) recovered significant detail at the cost of a "
     "checkerboard artefact on smooth gradients."),
]

for title, text in challenges:
    p = doc.add_paragraph(style="List Bullet")
    run = p.add_run(title + " — ")
    run.bold = True
    p.add_run(text)

doc.add_paragraph()

# ═════════════════════════════════════════════════════════════════════════════
# 8. AI USAGE DECLARATION
# ═════════════════════════════════════════════════════════════════════════════
h1("AI Usage Declaration")

para("Per the project rubric (pass/fail requirement), this section discloses "
     "any use of AI tools during the project.")
doc.add_paragraph()
para("Tools used:", bold=True)
bullet("Anthropic Claude (Claude Code CLI) — used to draft and iteratively "
       "refine the Verilog modules (cam_capture, ycbcr_to_rgb444, "
       "filter_pipeline, line_buffer3, filter_edge, vga_timing, sccb_master, "
       "frame_buffer, top.v), the cocotb 2.x Python testbenches in tests/640/ "
       "(test_cam_capture, test_vga_timing, test_frame_buffer, "
       "test_filter_pipeline, test_sccb_master, test_ycbcr_to_rgb444), "
       "and the legacy Verilog testbenches in sim/. All generated code was "
       "inspected, edited, and validated on hardware (Basys 3 + OV7670) and "
       "in simulation (Icarus Verilog) by the team.")
bullet("Anthropic Claude — used to help structure and draft this report "
       "(block diagram ASCII art, module description blocks, Q&A entries in "
       "the Design Decision section, challenge bullet points). Final wording "
       "and decisions reflect the team's actual experience.")
doc.add_paragraph()
para("Specific applications:", bold=True)
bullet("Code generation: SCCB FSM scaffolding, BT.601 luma multiply, "
       "antisymmetric chroma quantization bins, 3x3 line buffer sliding "
       "window, VGA 640x480 timing constants, cocotb test coroutines "
       "(ClockCycles, Timer, RisingEdge helpers).")
bullet("Debugging assistance: explaining iverilog scheduling races, "
       "narrowing the green-bias bug in the chroma decoder (non-antisymmetric "
       "bin offsets), locating the byte-pairing reset point in cam_capture, "
       "fixing V_TOTAL=521→525 (V_BP=29→33) to eliminate bottom black strip.")
bullet("Documentation: drafting this document and the README.")
doc.add_paragraph()
para("Not done by AI:", bold=True)
bullet("Hardware bring-up, oscilloscope / scope-on-LED debug, pin mapping "
       "verification, on-board demonstration tuning, and final architectural "
       "decisions (YCbCr 4:2:2 storage, Y3+Cb2+Cr2 bit depth, dither scheme, "
       "threshold values, V_TOTAL fix root-cause diagnosis).")

# ═════════════════════════════════════════════════════════════════════════════
# SAVE
# ═════════════════════════════════════════════════════════════════════════════
doc.save(str(OUT))
print(f"Saved: {OUT}")
