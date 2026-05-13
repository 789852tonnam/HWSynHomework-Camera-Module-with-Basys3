"""
cocotb tests for sources_1/new/camera_capture_640x320.v (320-path capture).

Downsample logic:
  - 2:1 horizontal: keep even camera pixels only (pxl_cnt[0] == 0)
  - 2:1 vertical:   keep even camera lines only (line_cnt[0] == 0)
  - PIXEL_SKIP=20:  discard first 20 camera pixels per line
  - write_col < 320: at most 320 fb columns per row

Data encoding: data_out = {b1[7:4], b1[2:0], d_in[7], d_in[4:1]}
  This extracts top-4 of R, top-4 of G, top-4 of B from RGB565.

Invariants checked:
  - No write_en for the first PIXEL_SKIP=20 pixels of any line
  - Writes occur only on even pxl_cnt (≥ 20)
  - Odd pxl_cnt pixels (≥ 20) do NOT produce write_en
  - Even camera lines produce writes; odd camera lines do NOT
  - addr_out for row 0 is in [0..319]; for row 1 in [320..639]
  - byte_sel resets on HREF fall (no byte-swap drift between lines)
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, FallingEdge

PCLK_PERIOD_NS = 20
PIXEL_SKIP     = 20   # must match localparam in camera_capture_640x320.v


async def _vsync_reset(dut):
    """Assert VSYNC to reset DUT state (line_cnt, row_base, etc.)."""
    dut.href.value  = 0
    dut.vsync.value = 1
    dut.d_in.value  = 0
    await ClockCycles(dut.pclk, 6)
    dut.vsync.value = 0
    await ClockCycles(dut.pclk, 2)


async def _send_pixel(dut, high: int, low: int):
    """Drive one RGB565 pixel; return write_en after second byte edge."""
    dut.d_in.value = high
    await RisingEdge(dut.pclk)
    dut.d_in.value = low
    await RisingEdge(dut.pclk)
    await FallingEdge(dut.pclk)  # NBA commits by falling edge; active region, driveable
    return int(dut.write_en.value)


async def _href_line(dut, n_pixels: int, high: int = 0xF8, low: int = 0x00):
    """
    Send n_pixels on one HREF line; return list of (pxl_cnt, write_en, addr_out).
    line_cnt is not observable directly — caller tracks it.
    """
    dut.href.value = 1
    results = []
    for p in range(n_pixels):
        we = await _send_pixel(dut, high, low)
        results.append((p, we, int(dut.addr_out.value)))
    dut.href.value = 0
    await ClockCycles(dut.pclk, 2)   # let old_href propagate
    return results


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_pixel_skip(dut):
    """First PIXEL_SKIP pixels of line 0 (even) must NOT produce write_en."""
    cocotb.start_soon(Clock(dut.pclk, PCLK_PERIOD_NS, unit="ns").start())
    await _vsync_reset(dut)

    dut.href.value = 1
    for p in range(PIXEL_SKIP):
        we = await _send_pixel(dut, 0xF8, 0x00)
        assert we == 0, f"write_en should be 0 for skipped pixel {p}"
    dut.href.value = 0


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_even_pixel_writes_odd_does_not(dut):
    """
    After PIXEL_SKIP, pixels with even pxl_cnt produce write_en=1;
    pixels with odd pxl_cnt do NOT (2:1 horizontal downsample).
    """
    cocotb.start_soon(Clock(dut.pclk, PCLK_PERIOD_NS, unit="ns").start())
    await _vsync_reset(dut)

    results = await _href_line(dut, PIXEL_SKIP + 10)
    # pxl_cnt = index within results (0-based)
    valid = [(p, we) for p, we, _ in results if p >= PIXEL_SKIP]

    for i, (p, we) in enumerate(valid):
        pxl_cnt = p   # pxl_cnt equals p (increments each completed pixel)
        expected_we = 1 if (pxl_cnt % 2 == 0) else 0
        assert we == expected_we, (
            f"pxl_cnt={pxl_cnt}: write_en={we} expected {expected_we}"
        )


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_odd_line_no_writes(dut):
    """Camera line 1 (odd line_cnt) must produce no write_en (vertical 2:1)."""
    cocotb.start_soon(Clock(dut.pclk, PCLK_PERIOD_NS, unit="ns").start())
    await _vsync_reset(dut)

    # Send line 0 (even) — some writes expected (ignore)
    await _href_line(dut, PIXEL_SKIP + 4)

    # Send line 1 (odd) — NO writes expected
    results = await _href_line(dut, PIXEL_SKIP + 4)
    for p, we, _ in results:
        assert we == 0, f"Line 1 (odd): pixel {p} produced write_en=1"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_row_base_advances(dut):
    """After line 0 (even), row_base advances by 320; line 1 (odd) does not."""
    cocotb.start_soon(Clock(dut.pclk, PCLK_PERIOD_NS, unit="ns").start())
    await _vsync_reset(dut)

    def first_write_addr(results):
        for _, we, addr in results:
            if we == 1:
                return addr
        return None

    # Line 0: first valid addr should be < 320
    r0 = await _href_line(dut, PIXEL_SKIP + 4)
    addr0 = first_write_addr(r0)
    assert addr0 is not None and addr0 < 320, (
        f"Line 0 write addr={addr0} expected < 320"
    )

    # Line 1 (odd): no writes
    await _href_line(dut, PIXEL_SKIP + 4)

    # Line 2 (even): row_base = 320 -> first addr >= 320
    r2 = await _href_line(dut, PIXEL_SKIP + 4)
    addr2 = first_write_addr(r2)
    assert addr2 is not None and addr2 >= 320, (
        f"Line 2 (even row 1) write addr={addr2} expected >= 320"
    )


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_byte_sel_reset_on_href_fall(dut):
    """
    byte_sel must reset on HREF fall so the next line always starts with
    the first byte (no byte-swap drift).
    """
    cocotb.start_soon(Clock(dut.pclk, PCLK_PERIOD_NS, unit="ns").start())
    await _vsync_reset(dut)

    # Send only 1 byte (leave byte_sel=1 mid-pixel) then drop HREF.
    # This partial line increments line_cnt: 0 -> 1 (odd).
    dut.href.value = 1
    dut.d_in.value = 0xF8
    await RisingEdge(dut.pclk)
    dut.href.value = 0              # fall mid-pixel; line_cnt 0->1
    await ClockCycles(dut.pclk, 3)

    # Line 1 (odd): no writes expected; line_cnt 1->2 at end.
    await _href_line(dut, PIXEL_SKIP + 4)

    # Line 2 (even): writes must occur if byte_sel was properly reset on each HREF fall.
    results = await _href_line(dut, PIXEL_SKIP + 4)
    valid_writes = [we for _, we, _ in results if we == 1]
    assert len(valid_writes) > 0, (
        "No writes on even line after HREF fall mid-pixel — byte_sel may not have reset"
    )
