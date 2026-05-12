# Real-Time Video Capture and Processing on Basys 3 + OV7670

A two-version FPGA video pipeline for the *HW Synthesis Lab I 2025/2 — Final Project*.
The board (Digilent **Basys 3**, Xilinx XC7A35T-1CPG236C) takes live video from an
**OV7670** camera over Pmod, processes the pixels in real time, and drives the
on-board **VGA** port at 640×480 @ 60 Hz.

Two complete pipelines live in the repo:

| Path | Resolution stored | Display | Top file | Frame buffer | Purpose |
| --- | --- | --- | --- | --- | --- |
| **320 path** (baseline) | 320×240 RGB444 | upscaled to 640×480 | `sources_1/new/top_module.v` | `frame_buffer_640x320.v` (76,800 × 12 b ≈ 30 BRAM) | Meets the **base requirement** in the brief: capture, store, display, four filter modes. |
| **640 path** (extra credit) | 640×480 YCbCr 4:2:2 | native 640×480 | `rtl/top.v` | `frame_buffer.v` (luma 307k × 3 b + chroma 153k × 4 b ≈ 50/50 BRAM split) | Goes for the **+5 EC** ("real 640×480"). Same four filters, native resolution, color preserved through 4:2:2 chroma subsampling. |

Both share the same **OV7670 init sequence**, the same **Sobel edge core**
(`filter_edge.v` + `line_buffer3.v`), and the same VGA timing skeleton.
They differ in *how* a 640×480 RGB565 stream gets squeezed into the 50 BRAM36
tiles available on the XC7A35T.

---

## 1. Project layout

```
HW-SynLab2025-main/
├── rtl/                              ← 640×480 YCbCr path (extra credit)
│   ├── top.v                          top-level
│   ├── clk_wiz_main.v                 MMCME2_BASE: 100 MHz → 25 + 24 MHz
│   ├── debouncer.v                    16×SW + BTNC debounce, two-flop sync
│   ├── cam_config.v                   power-up + 77-entry SCCB ROM walker
│   ├── sccb_master.v                  3-byte SCCB write FSM (open-drain)
│   ├── cam_capture.v                  OV7670 RGB565 → YCbCr 4:2:2 (Y3+Cb2/Cr2)
│   ├── frame_buffer.v                 split luma/chroma BRAMs, dual-clock
│   ├── cdc_pulse_sync.v               toggle-based 1-cycle pulse CDC
│   ├── vga_timing.v                   640×480 @ 60 Hz, mirror + flip
│   ├── filter_pipeline.v              RAW / INVERT / COLOR_ISO / EDGE selector
│   ├── ycbcr_to_rgb444.v              YCbCr → RGB444 with 2×2 Bayer dither
│   ├── line_buffer3.v                 3-line distributed RAM for 3×3 window
│   └── filter_edge.v                  3×3 Sobel on luma (L1 magnitude)
│
├── sources_1/new/                    ← 320×240 baseline path
│   ├── top_module.v                   top-level + state machine + line_buffer3 + filter_edge
│   ├── camera_capture_640x320.v       even-line/even-pixel downsample to 320×240
│   ├── frame_buffer_640x320.v         76,800 × 12 b BRAM
│   ├── vga_640x320_display.v          VGA timing + horizontal scale to 640
│   ├── sccb_config.v                  8-register SCCB init (4-phase FSM)
│   ├── sobel_edge_filter.v            unused alternative edge module
│   ├── filter_edge.v / line_buffer3.v copies of rtl versions for the 320 path
│   └── modules_append.v               appendable copy used by some Vivado scripts
│
├── constrs_1/new/
│   ├── constraints.xdc                pin map for sources_1 (top_module)
│   └── constraints_rtl.xdc            pin map for rtl (top)
│
├── sim/                              iverilog testbenches (Sobel, edge module)
├── tests/                            cocotb 2.x Python testbenches
│   ├── 640/                           six DUT targets for the rtl/ path
│   │   ├── test_cam_capture.py        cam_capture (YCbCr encode + pixel-skip)
│   │   ├── test_vga_timing.py         vga_timing  (counters, sync, fetch_active)
│   │   ├── test_filter_pipeline.py    filter_pipeline (RAW/INV/ISO/EDGE modes)
│   │   ├── test_frame_buffer.py       frame_buffer (luma/chroma split BRAM)
│   │   ├── test_sccb_master.py        sccb_master (FSM, busy/done, HALF_PER=4)
│   │   ├── test_ycbcr_to_rgb444.py    ycbcr_to_rgb444 (LUT + clamp + dither)
│   │   ├── run_tests.py               Python runner (no make required)
│   │   └── Makefile                   make-based runner
│   └── 320/                           four DUT targets for the sources_1/ path
│       ├── test_camera_capture.py     camera_capture_640x320
│       ├── test_vga_display.py        vga_640x320_display
│       ├── test_frame_buffer.py       frame_buffer_640x320
│       ├── test_sccb_config.py        sccb_config (8-register init sequence)
│       ├── run_tests.py               Python runner
│       └── Makefile
├── scripts/                          .tcl helpers for batch synth in Vivado
├── HW Synthesis Lab I 2025_2 - Final Project ... .pdf   the project brief
└── basys3_rm-1525374-17687320973847.pdf                 Basys 3 reference manual
```

---

## 2. Hardware setup

### Board
- **Digilent Basys 3**, FPGA: Xilinx **Artix-7 XC7A35T-1CPG236C**.
- 100 MHz on-board oscillator on **W5** (MRCC).
- 12-bit VGA via on-board resistor ladder (4 bits per channel).
- 16 slide switches, 5 push buttons (BTNC = U18 used as reset), 16 LEDs, 4-digit 7-seg.
- 50 × BRAM36 tiles (≈ 1.8 Mbits).

### Camera — OV7670
- Pmod headers carry an 8-bit data bus + sync signals + SCCB.
- `XCLK` (in)  ← 24 MHz from FPGA.
- `PCLK` (out) → ~24 MHz pixel clock back to FPGA on **A16** (a regular I/O pin, **not** clock-capable — see §6).
- `HREF`, `VSYNC` mark active rows / frames.
- `D[7:0]` — pixel byte stream; in RGB565 mode each pixel is two bytes (high, low).
- `SIOC`/`SIOD` (open-drain) — SCCB is I²C-like but no clock stretching; FPGA pulls up internally via `set_property PULLUP true` (no external pull-ups on Basys 3 Pmod pins).

### Pin mapping
Pin assignments are in `constrs_1/new/constraints*.xdc`. Both files target the same physical pads; only the port names change (`clk_100` vs `clk_100mhz`, `cam_*` vs `ov7670_*`, etc.). **In Vivado, only one xdc may be active at a time** — pick the one matching the top you set.

---

## 3. The brief, in one screen

From the project PDF:

- **Capture** OV7670 video, configure it via SCCB, store it in on-chip RAM.
- **Display** the captured frame on VGA in real time.
- **Four switch-selectable modes** on `SW[1:0]`:
  | `SW[1:0]` | Mode | Behavior |
  | --- | --- | --- |
  | `00` | Normal / RAW | display the captured frame |
  | `01` | Edge detection | 3×3 Sobel on luma; threshold from `SW[7:4]` |
  | `10` | Inversion | bitwise NOT of RGB |
  | `11` | Color isolation | keep one channel, suppress the other two; channel from `SW[3:2]` |

  *(In the rtl path, mode and color-iso bits are reorganized — see §5.5.)*

- **Extra credit (+5)**: do real **640×480**, not a downsampled 320×240.

---

## 4. The 320×240 path (baseline)

Lives entirely under `sources_1/new/`. Top file: `top_module.v`.

### 4.1 Data path

```
OV7670 (RGB565 @ pclk)
  └── camera_capture_640x320  ┐
        - byte_sel pairs two PCLK bytes → 16-bit pixel
        - DOWNSAMPLE: keep only (line_cnt[0]==0 && pxl_cnt[0]==0) → 320×240
        - emits {R[4:1], G[5:3], B[4:1]} = 12-bit RGB444 to RAM
        - addr_out 17 bits (≥ 76,800)
        - byte_sel reset on HREF falling edge — prevents the byte-swap drift
          that was the lab's most painful bug
        v
      frame_buffer_640x320     320×240 × 12-bit = 76,800 × 12 = ~14 BRAM18
        - true dual-clock: write @ pclk, read @ 25 MHz
        v
  ┌── vga_640x320_display      640×480 @ 60 Hz; combinational frame_addr
  │     - h_cnt 0..799, v_cnt 0..524, hsync/vsync active-low
  │     - HORIZONTAL UPSCALE: img_x = (h_cnt * 496) >> 10
  │       (maps h_cnt 0..639 → img_x 0..309 for PIXEL_SKIP=20 / 310 valid cols)
  │     - VERTICAL UPSCALE: img_y = v_cnt >> 1   (line doubling)
  │     - active_d & pixel_x_d & pixel_y_d are all registered 1 cycle
  └── pixel_in (12-bit RGB444) → State machine
        SW[1:0] selects RAW / EDGE / INVERSION / COLOR_ISO
        EDGE branch: feeds gray3 into line_buffer3 + filter_edge (see §7)
        ISO branch: SW[3:2] picks R/G/B/All
        v
       VGA pins (vga_r/g/b 4-bit, hsync, vsync)
```

### 4.2 What's clever about this path

- **Trivial frame buffer**: 320×240 × 12 b fits in well under half the BRAMs. No subsampling tricks needed.
- **`byte_sel` reset on HREF fall** (`camera_capture_640x320.v:43`): without this, a single missed PCLK between lines makes high/low bytes flip and every color goes wrong. This was the canonical OV7670 lab bug.
- **Combinational `frame_addr`**: end-to-end pipeline depth is only 1 cycle (BRAM read), so display alignment is essentially perfect. The 640 rebuild copies this style after a misadventure with deeper pipelining (see §5.6).
- **8-register SCCB** (`sccb_config.v`): minimum config for usable RGB565 output. Brutally simple, used as a fallback when the longer 77-register sequence had problems during bring-up.

### 4.3 Limits

- Half horizontal, half vertical resolution.
- Visible pixel doubling on edges of high-frequency detail.
- Doesn't satisfy the +5 EC.

---

## 5. The 640×480 path (extra credit)

Lives entirely under `rtl/`. Top file: `rtl/top.v`. **This is what the +5 EC is for.**

The hard problem: 640×480 × 12 b = 3.69 Mbits, but the chip has 1.84 Mbits of BRAM. We need ≈ 50% storage reduction *and* the result still has to look like color video. The strategy: **YCbCr 4:2:2 chroma subsampling** with very aggressive bit-depth reduction.

### 5.1 Storage budget — why YCbCr 4:2:2 and not RGB

| Encoding | Bits/pixel (avg) | Total for 640×480 | BRAM18 needed | Fits XC7A35T? |
| --- | --- | --- | --- | --- |
| RGB444 | 12 | 3.69 Mb | ~110 | NO (chip has ~100 BRAM18 = 50 BRAM36) |
| RGB332 | 8 | 2.46 Mb | ~73 | NO |
| **YCbCr 4:2:2 (Y3 + Cb2/Cr2)** | **3 + (2+2)/2 = 5** | **1.54 Mb** | **~46** | **YES** |
| Y3 only (mono) | 3 | 0.92 Mb | ~28 | YES (but no color) |

Why this works visually: human vision is much more sensitive to luminance than to chrominance. **4:2:2** keeps full-resolution luma (Y) per pixel and shares chroma (Cb, Cr) between every pair of horizontal pixels. That's the same trick JPEG, DV, HDMI 4:2:2, and basically every consumer video format uses.

We push it further than usual by quantizing aggressively: Y to 3 bits (8 levels) and each chroma component to **2 bits = 4 bins**. This is enough to keep recognizable color while halving the storage versus naive RGB444.

**Storage layout**:
- `luma_mem`: 307,200 × 3 bits → ~30 BRAM36 tiles
- `chroma_mem`: 153,600 × 4 bits (Cb2 || Cr2) → ~20 BRAM36 tiles
- **Total: 50/50 BRAM36** — full chip utilization.

### 5.2 Color encoding (cam_capture.v)

Each pair of OV7670 bytes is reassembled into a 16-bit RGB565 word, expanded to 8-bit per channel by replicating top bits, then converted to YCbCr using **BT.601 weights**:

```
Y8  = (77·R + 150·G + 29·B) >> 8
Cb2 = quantize(B - Y) into 4 bins (signed)
Cr2 = quantize(R - Y) into 4 bins (signed)

bin 0 : diff <  -48    strong deficit
bin 1 : -48 ≤ diff < 0 mild deficit (neutral side)
bin 2 :  0 ≤ diff < 48 mild positive
bin 3 : diff ≥ 48      strong positive
```

`Y3 = Y8[7:5]` is 3 bits, written every pixel.
`{Cb2, Cr2}` is 4 bits, written **only on even columns** (`wr_chroma_en = ~col_phase`). Odd columns reuse the chroma their even neighbor wrote — this is exactly 4:2:2 subsampling.

The byte-pair / `byte_sel` / `old_href` discipline is copied verbatim from the 320 path because it was the proven-correct piece.

### 5.3 Frame buffer (frame_buffer.v)

```
write @ cam_pclk          read @ clk_25
─────────────────         ──────────────
luma_mem[wr_addr]   ──→   luma_mem[rd_addr]                → rd_luma  (3 b, 1-cycle latency)
chroma_mem[wr_addr>>1] ──→ chroma_mem[rd_addr>>1]          → rd_chroma (4 b)
```

True dual-clock BRAMs handle the pclk↔25 MHz domain crossing at the byte level. No FIFO is needed — the camera writes at ≈ pclk and the VGA scanner reads at 25 MHz. The two clocks are deliberately treated as **asynchronous** in `constraints_rtl.xdc` (`set_clock_groups -asynchronous`); BRAM hardware handles sync internally.

### 5.4 Decoding back to RGB444 (ycbcr_to_rgb444.v)

The reverse is a 4-entry LUT per chroma component, plus a **2×2 Bayer dither** to recover one extra effective bit of luma:

```
y4 = {y3, dither},  dither = h_count[0] ^ v_count[0]
R4 = clamp(y4 + r_off(Cr))
B4 = clamp(y4 + b_off(Cb))
G4 = clamp(y4 + g_off_cr(Cr) + g_off_cb(Cb))
```

The LUT entries are tuned so that **bin-1 inputs (the bin a neutral pixel lands in) decode to offset 0** — otherwise the whole image gets a green tint. The Cb→G and Cr→G offsets follow BT.601 shape: Cr influences G about twice as much as Cb does.

| | bin 0 | bin 1 | bin 2 | bin 3 |
| --- | --- | --- | --- | --- |
| `r_off` (Cr→R) | −3 | −1 | +1 | +3 |
| `b_off` (Cb→B) | −3 | −1 | +1 | +3 |
| `g_off_cr` (Cr→G) | +2 | +1 | −1 | −2 |
| `g_off_cb` (Cb→G) | +1 | 0 | 0 | −1 |

The 2×2 Bayer dither is the standard cheap way to reduce posterization when bit-truncating: alternating ±0.5 LSB in a checkerboard makes the eye integrate to a smoother gradient instead of seeing flat steps.

### 5.5 Switch / LED map

| Range | Function |
| --- | --- |
| `SW[1:0]` | Filter mode: 00=RAW, 01=INVERT, 10=COLOR_ISO, 11=EDGE |
| `SW[3:2]` | Color isolation channel (in mode 10): 00=R, 01=G, 10=B, 11=R |
| `SW[7:4]` | Sobel edge threshold (in mode 11), 4-bit unsigned |
| `SW[8]` | OV7670 internal color-bar test pattern (extra SCCB writes) |
| `SW[9]` | FPGA-side test pattern bypass — replaces camera writes with synthetic R/G/B vertical bars (sanity test for the chroma decoder without needing the camera) |
| `BTNC` | system reset |
| `LD[15]` | `cfg_done` — SCCB init complete |
| `LD[14]` | toggles every camera VSYNC (frame-rate liveness) |
| `LD[13:8]` | low 6 bits of `reg_writes_done` count |
| `LD[7:0]` | passthrough of `SW[7:0]` for visual confirmation |

### 5.6 Pipeline depth and pixel alignment

This is the **single most error-prone aspect** of the 640 path. The depth from `vga_timing.h_count` advancing to a pixel reaching the VGA pin is:

| Stage | Cycles | Comment |
| --- | --- | --- |
| `rd_addr` from `h_count` | **0** | combinational in `vga_timing.v` (matches 320 path) |
| `frame_buffer` BRAM read | **1** | always-1 for synchronous BRAM |
| `filter_pipeline` (all modes) | **2** | RAW/INV/ISO: `raw_d` latch + output reg; EDGE: `line_buffer3` + output reg |
| **Total (all modes)** | **3** | latencies matched inside `filter_pipeline` so mode switch causes no H-shift |

The `active_video` signal is therefore delayed **3 cycles** before gating the VGA output (`active_pipe[2]` in `top.v`). A 3-cycle pre-fetch window (`h_count` 797–799) issues `rd_addr` for the next line's first three pixels so `active_d` can rise cleanly at `h_count = 0`. Earlier rebuilds had a 4-cycle pipeline (registered `rd_addr` + per-mode latency-match latches) and produced a visible 4-pixel rightward content shift — fixed by stripping out the redundant registers and matching the 320 path's combinational style.

### 5.7 Geometric corrections (vga_timing.v)

The OV7670 outputs frames in scan order with origin at the top-left of *its* sensor, which on this Pmod orientation comes out **upside-down and mirrored** relative to the VGA scanner. Two cheap fixes, both inside `rd_addr`:

```
line_base counts DOWN from row 479 → row 0          (vertical flip)
h_scaled = floor(eff_h × 998 / 1024)                (scale 0..624 → 0..623 in VALID_COLS)
mirror_x = (VALID_COLS − 1) − h_scaled              (horizontal mirror; coeff 998 = ⌊623×1024/639⌋)
```

`line_base` is a running accumulator (subtract 640 each new line) — no multiplier inferred, just a 19-bit subtractor. The coefficient 998 maps the 624 valid fb columns onto the 640 display columns with the horizontal mirror baked in. `eff_h` is `h_count + PIPE` during the active region and `h_count − PREFETCH_START` during the 3-cycle pre-fetch window.

---

## 6. Cross-cutting engineering techniques

These appear in both paths and are the kinds of things any new contributor needs to know about.

### 6.1 Clocks
- **MMCME2_BASE** (`rtl/clk_wiz_main.v`) generates 25 MHz (VGA pixel) and 24 MHz (camera XCLK) from the 100 MHz board clock. VCO at 1200 MHz, both outputs through `BUFG`.
- The same module has an `\`ifdef SYNTHESIS` guard that swaps in behavioral clock generators for iverilog simulation, so the design still simulates without needing to vendor-supply UNISIM.
- The 320 path uses Vivado's `clk_wiz_0` IP for the same job.

### 6.2 PCLK on a non-clock-capable pin
The OV7670 PCLK arrives on **A16**, which is *not* a clock-capable input on Basys 3. Vivado refuses to route it like a real clock by default. Both xdc files apply:

```tcl
create_clock -period 40.000 -name cam_pclk_pin [get_ports cam_pclk]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets cam_pclk_IBUF]
```

This downgrades the PCLK net to general-fabric routing — fine at 25 MHz on this small design, but worth flagging as a known compromise.

### 6.3 Cross-domain crossing
- **Frame buffer** itself: a true dual-clock BRAM is the entire CDC for the pixel data. Pclk side writes, 25 MHz side reads. Tearing is acceptable (it's a video preview, no double-buffering).
- **VSYNC pulse → LED toggle**: a single 1-cycle pulse needs to cross from cam_pclk to clk_25. `cdc_pulse_sync.v` uses the standard **toggle-flop + 3-FF synchronizer + edge-detect** trick, marked with `(* ASYNC_REG = "TRUE" *)` so Vivado packs the synchronizer flops in the same slice for minimum metastability MTBF.
- **Async clock groups**: `set_clock_groups -asynchronous` between `sys_clk` and `cam_pclk_pin` tells Vivado to ignore inter-domain timing arcs for setup/hold.

### 6.4 SCCB
The OV7670 needs roughly 80 register writes before it will output anything sensible (color matrix, gamma curve, AGC/AEC, several "magic" undocumented registers from the OV7670 community).

- **`rtl/sccb_master.v`** is a from-scratch 7-state FSM doing one **3-byte write** per `start` pulse (ID byte | sub-addr | data, with a "don't care" ACK slot after each). Bus is open-drain — `assign sda = sda_low ? 1'b0 : 1'bz;` plus board pull-ups.
- **`rtl/cam_config.v`** drives `cam_master`, holds `cam_rst_n` low for 25 ms, releases it, sends a soft-reset, waits 30 ms (the OV7670 datasheet minimum), then walks a 77-entry ROM with ~100 µs gaps. It tracks ACKs in `successful_xacts`, exposed on LEDs for bring-up.
- **`sources_1/new/sccb_config.v`** is the simpler 8-register baseline equivalent — adequate for the 320 path.

### 6.5 Debouncing
`debouncer.v` is a generic W-bit module with a per-bit two-flop synchronizer and an N-bit stability counter. With `N=20`, an input must be stable for 2²⁰ clocks (~42 ms at 25 MHz) before its output flips. Used for all switches and BTNC.

### 6.6 Line-buffer hazard handling (line_buffer3.v)
The 3×3 Sobel needs three rows of 3-bit luma, kept in three `WIDTH × 3` distributed RAMs. Each cycle the design writes the new pixel into the "bottom" buffer and reads a 3×3 window from all three.

The trap: reading **bottom-row column h** (== current `h_count`) from the same buffer we're writing this cycle returns the *old* value (read-before-write on distributed RAM). Solution: **forward `pix_in` directly to `bot_r`** instead of reading the buffer. Columns h-2 and h-1 (`bot_l`, `bot_c`) are safe — they were committed 2 and 1 cycles ago.

### 6.7 Sobel arithmetic (filter_edge.v)
- 3-bit luma values 0..7. Weighted column/row sums max out at 7+14+7 = 28 → fits in 5 bits.
- `Gx`, `Gy` are signed 6-bit differences. `|Gx| + |Gy|` (the **L1 magnitude approximation**) fits in 7 bits.
- L1 instead of `√(Gx² + Gy²)` because we don't have a multiplier or sqrt budget for the per-pixel rate, and L1 is good enough for a binary edge map.
- Frame-edge pixels (`h_edge`, `v_edge`) are forced black to suppress the garbage that the unbounded 3×3 window would otherwise produce there.

---

## 7. Common Sobel building blocks (shared between paths)

`line_buffer3.v` and `filter_edge.v` exist in *both* `sources_1/new/` and `rtl/` — the 320 path's `top_module.v` instantiates them too, fed from a 3-bit gray approximation `(R + G + B) / 3`. The two copies are byte-identical except for the tiny stylistic difference that the rtl version uses the `bot_r` forwarding trick described above; the 320 version doesn't need it because the latency budget hides the read-during-write (1-cycle later doesn't matter when the entire pipeline is 1 cycle).

---

## 8. Building / running

### Vivado (synthesis & bitstream)
1. Open `project_2/project_2.xpr` (or create a new project pointing at one of the source folders).
2. **Pick which path to build**:
   - 320 path: enable `sources_1/new/*.v`, set `top_module` as top, enable `constrs_1/new/constraints.xdc`, **disable** `constraints_rtl.xdc`.
   - 640 path: enable `rtl/*.v`, set `top` as top, enable `constraints_rtl.xdc`, **disable** `constraints.xdc`.
3. Run synthesis → implementation → generate bitstream → program board.
4. The `scripts/*.tcl` files automate parts of this for batch runs.

### Simulation

**iverilog (Verilog testbenches, `sim/`)**
```bash
iverilog -g2012 -o sim_top rtl/*.v
```
Legacy Verilog testbenches under `sim/320/` and `sim/640/` cover the major sub-modules.

**cocotb 2.x (Python testbenches, `tests/`)**
Requires `cocotb >= 2.0` and `iverilog` on PATH.
```bash
# 640 path — six targets
cd tests/640
python run_tests.py                          # all six
python run_tests.py cam_capture sccb_master  # subset
# or via make: make cam_capture / make all

# 320 path — four targets
cd tests/320
python run_tests.py                          # all four
# or via make: make all
```
**640 targets:** `cam_capture`, `vga_timing`, `filter_pipeline`, `frame_buffer`, `sccb_master`, `ycbcr_to_rgb444`

**320 targets:** `camera_capture`, `vga_display`, `frame_buffer`, `sccb_config`

`sccb_master` is compiled with `HALF_PER_CYCLES=4` (instead of the default 128) so the simulation completes in ~250 cycles instead of ~7900.

Each target rebuilds the DUT with icarus and runs the corresponding `test_*.py`.

> **Windows note:** `run_tests.py` requires Python from [python.org](https://www.python.org/downloads/), not the Windows Store version. The Windows Store AppContainer sandbox prevents C-extension DLLs from loading when Python is embedded inside `vvp`. WSL works without modification.

### On-board sanity checks
1. After programming, **LD[15]** (`cfg_done`) lights within ~1 second.
2. **LD[14]** starts toggling at ~30 Hz once camera VSYNCs are arriving.
3. Aim camera at white wall → output should be white/gray (no green wash).
4. Toggle `SW[9]` (rtl path) → three full-saturation R/G/B vertical bars confirm the YCbCr → RGB444 decoder independently of the camera.
5. Step `SW[1:0]` 00→01→10→11 and confirm each filter mode behaves.
6. Crank `SW[7:4]` from 0x0 → 0xF in EDGE mode and watch edges thin out.

---

## 9. History / development notes

- **320 path** was the first version that worked end-to-end. The byte-swap fix in `camera_capture_640x320.v:43` (`byte_sel <= 0` on the HREF falling edge) was the single most important bring-up moment.
- **640 path** went through several rebuilds:
  1. RGB565 attempt — didn't fit BRAM.
  2. RGB332 — fit BRAM, looked terrible.
  3. Mono Y3 — fit easily, looked great but lost color (the brief implies color is expected).
  4. **YCbCr 4:2:2** (current) — keeps color, fits BRAM, looks acceptable.
- During the YCbCr rebuild, two visible artifacts had to be hunted: a green tint (chroma decoder LUT had a non-zero offset for the neutral bin) and a 4-pixel right shift (over-pipelined `rd_addr`). Both are documented in commit history (`a37eb06`).

---

## 10. Known limits / things a successor might tackle

- **Color fidelity** is "recognizable color" not "accurate color" — 2 bits of chroma per pair is a hard ceiling. Going to Cb3/Cr3 would need either ZIP-tier compression or another BRAM strategy.
- **Shimmering on fine detail** in EDGE mode — sub-pixel jitter from running Sobel on aggressively quantized luma. Adding a small pre-filter (3-tap horizontal blur) would help but cost a third line buffer.
- **PCLK on A16** is non-ideal; future revisions could swap to a clock-capable Pmod pin and remove the `CLOCK_DEDICATED_ROUTE FALSE` workaround.
- **Tearing**: there's no double buffer. At 60 Hz read vs. ~30 Hz write, you get a moving tear band. Acceptable for a preview, but a true double buffer would need ~3 Mbits more, which the chip can't supply.
- **AGC/AEC** are enabled in the long SCCB ROM; the camera adjusts exposure on its own. The settle takes several seconds at power-up.

---

## 11. Where to look in the source first

If you have 5 minutes:
- `rtl/top.v` — top-level wiring and switch/LED map (640 path)
- `sources_1/new/top_module.v` — same for 320 path

If you have 30 minutes:
- `rtl/cam_capture.v` — RGB565 → YCbCr quantization (the actual pixel math)
- `rtl/ycbcr_to_rgb444.v` — and back again
- `rtl/frame_buffer.v` — split BRAM strategy
- `rtl/vga_timing.v` — alignment and geometric flips
- `filter_edge.v` + `line_buffer3.v` — the only real arithmetic in the design

If you have an afternoon:
- read `rtl/cam_config.v` and `rtl/sccb_master.v` together — this is the part that turns "no signal" into "signal" and where most bring-up time goes
- read `rtl/cdc_pulse_sync.v` and the `set_clock_groups` lines in `constraints_rtl.xdc` — they're the formal record of what the design considers asynchronous
- diff the 320 vs 640 versions of `line_buffer3.v` to see why the rtl one needed `pix_in` forwarding

Both PDFs (`HW Synthesis Lab I 2025_2 - Final Project.pdf` and the Basys 3 reference manual) are in the repo root for reference.
