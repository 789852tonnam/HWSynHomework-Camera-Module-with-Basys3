"""
cocotb tests for rtl/frame_buffer.v (split luma + chroma dual-clock BRAM).

Geometry:
  luma_mem:   307,200 entries × 3 bits  (one Y3 per pixel)
  chroma_mem: 153,600 entries × 4 bits  (Cb2/Cr2 per even-col pixel pair)
  chroma address = wr_addr[18:1]  — adjacent even/odd pixels share one word

Invariants checked:
  - Luma write → read-back with 1-cycle BRAM latency
  - wr_chroma_en=0 does NOT overwrite chroma
  - Chroma 4:2:2 sharing: odd pixel reads the same chroma word as its even neighbour
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CLK_PERIOD_NS = 10   # one clock drives both ports (avoids CDC for test simplicity)


async def _write_pixel(dut, addr: int, luma: int, chroma: int, chroma_en: int):
    """Write one pixel (luma + optional chroma) on wr_clk posedge."""
    dut.wr_addr.value      = addr
    dut.wr_luma.value      = luma
    dut.wr_chroma.value    = chroma
    dut.wr_chroma_en.value = chroma_en
    dut.wr_en.value        = 1
    await RisingEdge(dut.wr_clk)
    dut.wr_en.value = 0
    await RisingEdge(dut.wr_clk)   # deassert settles


async def _read_pixel(dut, addr: int):
    """Read luma and chroma at addr with 1-cycle BRAM latency."""
    dut.rd_addr.value = addr
    await RisingEdge(dut.rd_clk)   # address registered
    await RisingEdge(dut.rd_clk)   # data out (1-cycle latency)
    return int(dut.rd_luma.value), int(dut.rd_chroma.value)


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_luma_write_readback(dut):
    """Write distinct luma values to several addresses; read them back."""
    cocotb.start_soon(Clock(dut.wr_clk, CLK_PERIOD_NS, units="ns").start())

    dut.rd_clk.value       = 0
    dut.rd_addr.value      = 0
    dut.wr_en.value        = 0
    dut.wr_chroma_en.value = 0
    await ClockCycles(dut.wr_clk, 2)

    # Piggyback rd_clk from wr_clk for test simplicity
    cocotb.start_soon(Clock(dut.rd_clk, CLK_PERIOD_NS, units="ns").start())
    await ClockCycles(dut.wr_clk, 2)

    test_cases = [
        (0,       3, 0xA, 1),
        (1,       5, 0xB, 1),
        (639,     7, 0xC, 1),
        (640,     1, 0xD, 1),
        (307199,  2, 0xE, 1),
    ]

    for addr, luma, chroma, cen in test_cases:
        await _write_pixel(dut, addr, luma, chroma, cen)

    for addr, exp_luma, exp_chroma, _ in test_cases:
        got_luma, got_chroma = await _read_pixel(dut, addr)
        assert got_luma == exp_luma, (
            f"addr={addr}: luma got={got_luma} exp={exp_luma}"
        )


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_chroma_4to2to2_sharing(dut):
    """
    Even address writes chroma; odd address (same pair) reads the same word.
    Even addr=0 and odd addr=1 share chroma_mem[0].
    """
    cocotb.start_soon(Clock(dut.wr_clk, CLK_PERIOD_NS, units="ns").start())
    cocotb.start_soon(Clock(dut.rd_clk, CLK_PERIOD_NS, units="ns").start())

    dut.wr_en.value        = 0
    dut.wr_chroma_en.value = 0
    await ClockCycles(dut.wr_clk, 2)

    # Write pixel 0 (even): luma=1, chroma=0xA, chroma_en=1
    await _write_pixel(dut, 0, 1, 0xA, 1)
    # Write pixel 1 (odd): luma=2, chroma=0x0, chroma_en=0 (should NOT overwrite)
    await _write_pixel(dut, 1, 2, 0x0, 0)

    _, chroma0 = await _read_pixel(dut, 0)
    _, chroma1 = await _read_pixel(dut, 1)

    assert chroma0 == 0xA, f"pixel 0 chroma={chroma0:#x} expected 0xA"
    assert chroma1 == 0xA, (
        f"pixel 1 chroma={chroma1:#x} should share 0xA with pixel 0 (4:2:2)"
    )


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_chroma_en_gate(dut):
    """wr_chroma_en=0 must NOT overwrite an existing chroma value."""
    cocotb.start_soon(Clock(dut.wr_clk, CLK_PERIOD_NS, units="ns").start())
    cocotb.start_soon(Clock(dut.rd_clk, CLK_PERIOD_NS, units="ns").start())

    dut.wr_en.value        = 0
    dut.wr_chroma_en.value = 0
    await ClockCycles(dut.wr_clk, 2)

    # Write chroma=0xF at address 2 (even, chroma_en=1)
    await _write_pixel(dut, 2, 3, 0xF, 1)
    # Attempt overwrite with chroma_en=0
    await _write_pixel(dut, 2, 3, 0x0, 0)

    _, chroma = await _read_pixel(dut, 2)
    assert chroma == 0xF, (
        f"chroma_en=0 must not overwrite; got chroma={chroma:#x} expected 0xF"
    )
