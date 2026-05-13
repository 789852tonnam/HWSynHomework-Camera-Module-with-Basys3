"""
cocotb tests for rtl/filter_pipeline.v (all 4 filter modes).

Pipeline depth: BRAM-read (not modelled here) + filter = 2 cycles from input to output.
  raw_d / inv_d / iso_d: 1 latch + 1 output reg = 2 cycles
  edge (line_buffer3 + output reg): also 2 cycles
Inputs must be stable for 2 cycles before sampling rgb444_out.

Mode encoding (sw_mode):
  00 = RAW       (YCbCr -> RGB444)
  01 = INVERT    (bitwise NOT of RAW)
  10 = COLOR_ISO (pass selected channel; sw32: 00=R, 01=G, 10=B)
  11 = EDGE      (3×3 Sobel on luma; flat field -> 0)
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CLK_PERIOD_NS  = 10   # 100 MHz — faster than real 25 MHz for quick sim
PIPE_DEPTH     = 4    # settle margin (pipeline=2, give +2 extra)
WIDTH          = 640


async def _reset(dut):
    dut.rst.value      = 1
    dut.fb_luma.value  = 0
    dut.fb_chroma.value = 0
    dut.h_count.value  = 100
    dut.v_count.value  = 100
    dut.pix_valid.value = 1
    dut.sw_mode.value  = 0
    dut.sw32.value     = 0
    dut.sw74.value     = 1
    dut.h_edge.value   = 0
    dut.v_edge.value   = 0
    await ClockCycles(dut.clk, 4)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)


async def _settle(dut, cycles=PIPE_DEPTH):
    await ClockCycles(dut.clk, cycles)


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_raw_nonzero(dut):
    """RAW mode: mid-gray luma + mild chroma -> non-zero RGB444 output."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    dut.fb_luma.value   = 4          # mid-gray
    dut.fb_chroma.value = 0b1010     # cb=2 (mild+), cr=2 (mild+)
    dut.sw_mode.value   = 0b00       # RAW
    await _settle(dut)

    raw = int(dut.rgb444_out.value)
    assert raw != 0, f"RAW mode: expected non-zero output for mid-gray, got {raw:#05x}"
    return raw   # captured for invert test


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_invert(dut):
    """INVERT mode must produce bitwise NOT of the RAW output for same input."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    dut.fb_luma.value   = 4
    dut.fb_chroma.value = 0b1010
    dut.sw_mode.value   = 0b00    # RAW
    await _settle(dut)
    raw = int(dut.rgb444_out.value)

    dut.sw_mode.value = 0b01      # INVERT
    await _settle(dut)
    inv = int(dut.rgb444_out.value)

    assert inv == (~raw & 0xFFF), (
        f"INVERT: got {inv:#05x}, expected ~raw={~raw & 0xFFF:#05x}"
    )


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_color_iso_r(dut):
    """COLOR_ISO sw32=00: only R nibble non-zero; G and B must be 0."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    dut.fb_luma.value   = 4
    dut.fb_chroma.value = 0b1110    # cb=3 (strong+), cr=2 (mild+) -> R non-zero
    dut.sw_mode.value   = 0b10
    dut.sw32.value      = 0b00     # isolate R
    await _settle(dut)

    out = int(dut.rgb444_out.value)
    r = (out >> 8) & 0xF
    g = (out >> 4) & 0xF
    b =  out       & 0xF
    assert g == 0 and b == 0, f"ISO_R: G={g} B={b} should be 0 (out={out:#05x})"
    assert r != 0,            f"ISO_R: R nibble is 0 (out={out:#05x})"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_color_iso_g(dut):
    """COLOR_ISO sw32=01: only G nibble non-zero; R and B must be 0."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    dut.fb_luma.value   = 5
    dut.fb_chroma.value = 0b0000    # neutral -> G should be non-zero (Y drives G)
    dut.sw_mode.value   = 0b10
    dut.sw32.value      = 0b01     # isolate G
    await _settle(dut)

    out = int(dut.rgb444_out.value)
    r = (out >> 8) & 0xF
    g = (out >> 4) & 0xF
    b =  out       & 0xF
    assert r == 0 and b == 0, f"ISO_G: R={r} B={b} should be 0 (out={out:#05x})"
    assert g != 0,            f"ISO_G: G nibble is 0 (out={out:#05x})"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_color_iso_b(dut):
    """COLOR_ISO sw32=10: only B nibble non-zero; R and G must be 0."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    dut.fb_luma.value   = 4
    dut.fb_chroma.value = 0b1100    # cb=3 (strong blue), cr=0
    dut.sw_mode.value   = 0b10
    dut.sw32.value      = 0b10     # isolate B
    await _settle(dut)

    out = int(dut.rgb444_out.value)
    r = (out >> 8) & 0xF
    g = (out >> 4) & 0xF
    b =  out       & 0xF
    assert r == 0 and g == 0, f"ISO_B: R={r} G={g} should be 0 (out={out:#05x})"
    assert b != 0,            f"ISO_B: B nibble is 0 (out={out:#05x})"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_edge_flat_field(dut):
    """
    EDGE mode on a flat field (constant luma) -> Sobel magnitude = 0 -> rgb444 = 0.
    Fill 3 rows of line_buffer3 with constant luma, then check output.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    LUMA = 4

    dut.sw_mode.value   = 0b11    # EDGE
    dut.sw74.value      = 1       # threshold = 1 (edge if mag >= 2)
    dut.fb_luma.value   = LUMA
    dut.fb_chroma.value = 0
    dut.pix_valid.value = 1

    # Fill line_buffer3: scan 3 rows × WIDTH columns
    for row in range(3):
        for col in range(WIDTH):
            dut.h_count.value = col
            dut.v_count.value = row
            await RisingEdge(dut.clk)

    # Sample at an interior pixel (not at frame edge)
    dut.h_count.value = 100
    dut.v_count.value = 2
    dut.h_edge.value  = 0
    dut.v_edge.value  = 0
    await _settle(dut)

    out = int(dut.rgb444_out.value)
    assert out == 0, (
        f"EDGE on flat luma={LUMA}: expected 0 (Sobel=0), got {out:#05x}"
    )
