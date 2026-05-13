"""
cocotb tests for rtl/cam_capture.v (640-path camera capture).

Invariants checked:
  - First PIXEL_SKIP=16 pixels per HREF line do NOT produce wr_en
  - Pixel 16+ produces wr_en=1, with correct wr_luma and wr_chroma
  - VSYNC resets row_base/write_col and fires vsync_pulse
  - HREF fall increments row_base by 640
  - wr_chroma_en follows write_col parity (1 on even, 0 on odd)
  - YCbCr math for pure-red RGB565: luma=2, chroma={cb2=0,cr2=3}=0x3
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, FallingEdge

PCLK_PERIOD_NS = 20   # 50 MHz — fast for sim; real cam is ~24 MHz
PIXEL_SKIP     = 16   # must match localparam in cam_capture.v


async def _reset_via_vsync(dut):
    """Assert VSYNC for a few cycles to put DUT into a clean start state."""
    dut.href.value  = 0
    dut.vsync.value = 1
    dut.d_in.value  = 0
    await ClockCycles(dut.pclk_in, 6)
    dut.vsync.value = 0
    await ClockCycles(dut.pclk_in, 2)


async def _send_pixel(dut, high: int, low: int):
    """
    Drive one RGB565 pixel as two consecutive PCLK bytes.
    After return, wr_en / wr_luma / wr_chroma reflect values registered
    at the second (low) byte edge.
    """
    # First byte: DUT captures into b1 (byte_sel 0->1)
    dut.d_in.value = high
    await RisingEdge(dut.pclk_in)
    # Second byte: DUT completes pixel (byte_sel 1->0), may set wr_en
    dut.d_in.value = low
    await RisingEdge(dut.pclk_in)
    await FallingEdge(dut.pclk_in)  # NBA commits by falling edge; active region, driveable


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_pixel_skip(dut):
    """First PIXEL_SKIP pixels per HREF line must NOT generate wr_en."""
    cocotb.start_soon(Clock(dut.pclk_in, PCLK_PERIOD_NS, unit="ns").start())
    await _reset_via_vsync(dut)

    dut.href.value = 1
    for p in range(PIXEL_SKIP):
        await _send_pixel(dut, 0xF8, 0x00)   # red-ish, value irrelevant
        assert dut.wr_en.value == 0, (
            f"wr_en asserted for skipped pixel {p} (expect 0 for first {PIXEL_SKIP})"
        )
    dut.href.value = 0


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_ycbcr_pure_red(dut):
    """
    Pure red RGB565 (R5=31 G6=0 B5=0 -> 0xF800):
      r8=255, g8=0, b8=0
      Y8 = (77*255) >> 8 = 76  -> y3 = 76[7:5] = 2
      diff_r = 255 - 76 = 179 ≥ 48  -> cr2 = 3
      diff_b = 0   - 76 = -76 < -48 -> cb2 = 0
      wr_luma  = 2
      wr_chroma = {cb2=0, cr2=3} = 0x3
    """
    cocotb.start_soon(Clock(dut.pclk_in, PCLK_PERIOD_NS, unit="ns").start())
    await _reset_via_vsync(dut)

    dut.href.value = 1
    # Skip first PIXEL_SKIP pixels (outputs don't matter)
    for _ in range(PIXEL_SKIP):
        await _send_pixel(dut, 0x00, 0x00)

    # Now send one pure-red pixel
    await _send_pixel(dut, 0xF8, 0x00)

    assert dut.wr_en.value    == 1, "wr_en should be 1 for valid pixel"
    assert dut.wr_luma.value  == 2, f"wr_luma={int(dut.wr_luma.value)} expected 2"
    assert dut.wr_chroma.value == 3, f"wr_chroma={int(dut.wr_chroma.value)} expected 3 ({{cb2=0,cr2=3}})"

    dut.href.value = 0


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_vsync_pulse_and_reset(dut):
    """VSYNC asserts vsync_pulse and clears wr_en."""
    cocotb.start_soon(Clock(dut.pclk_in, PCLK_PERIOD_NS, unit="ns").start())

    dut.href.value  = 0
    dut.vsync.value = 0
    dut.d_in.value  = 0
    await ClockCycles(dut.pclk_in, 4)

    dut.vsync.value = 1
    await RisingEdge(dut.pclk_in)
    await FallingEdge(dut.pclk_in)  # NBA committed: vsync_pulse=1, wr_en=0
    assert dut.vsync_pulse.value == 1, "vsync_pulse should be 1 while vsync is high"
    assert dut.wr_en.value       == 0, "wr_en must be 0 during vsync"

    dut.vsync.value = 0
    await RisingEdge(dut.pclk_in)
    await FallingEdge(dut.pclk_in)  # NBA committed: vsync_pulse=0
    assert dut.vsync_pulse.value == 0, "vsync_pulse must deassert next cycle"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_row_base_advances(dut):
    """wr_addr base increments by 640 after each complete HREF line."""
    cocotb.start_soon(Clock(dut.pclk_in, PCLK_PERIOD_NS, unit="ns").start())
    await _reset_via_vsync(dut)

    async def href_line(n_pixels: int):
        """Send n_pixels red pixels on one HREF line, return first wr_addr seen."""
        dut.href.value = 1
        first_addr = None
        for _ in range(n_pixels):
            await _send_pixel(dut, 0xF8, 0x00)
            if first_addr is None and dut.wr_en.value == 1:
                first_addr = int(dut.wr_addr.value)
        dut.href.value = 0
        await ClockCycles(dut.pclk_in, 2)   # inter-line gap so old_href propagates
        return first_addr

    addr0 = await href_line(PIXEL_SKIP + 2)
    addr1 = await href_line(PIXEL_SKIP + 2)

    assert addr0 is not None, "No write on line 0"
    assert addr1 is not None, "No write on line 1"
    assert addr1 - addr0 == 640, (
        f"row_base should advance by 640; got addr0={addr0} addr1={addr1}"
    )


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_chroma_en_alternates(dut):
    """wr_chroma_en should be 1 for even write_col and 0 for odd."""
    cocotb.start_soon(Clock(dut.pclk_in, PCLK_PERIOD_NS, unit="ns").start())
    await _reset_via_vsync(dut)

    dut.href.value = 1
    # Skip
    for _ in range(PIXEL_SKIP):
        await _send_pixel(dut, 0xF8, 0x00)

    # Collect chroma_en for 8 valid writes
    pattern = []
    for _ in range(8):
        await _send_pixel(dut, 0xF8, 0x00)
        if dut.wr_en.value == 1:
            pattern.append(int(dut.wr_chroma_en.value))

    dut.href.value = 0

    assert len(pattern) >= 6, f"Too few writes captured: {pattern}"
    for i, ce in enumerate(pattern):
        expected = 1 if (i % 2 == 0) else 0
        assert ce == expected, (
            f"chroma_en[write_col={i}]={ce} expected {expected}"
        )
