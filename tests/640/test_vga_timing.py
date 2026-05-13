"""
cocotb tests for rtl/vga_timing.v (640-path VGA timing generator).

VGA 640x480 @ 60 Hz — standard VESA timing:
  H_TOTAL = 800  (active=640, FP=16, sync=96, BP=48)
  V_TOTAL = 525  (active=480, FP=10, sync=2,  BP=33)
  HSYNC active-LOW: h in [656..751]
  VSYNC active-LOW: v in [490..491]
  PIXEL_SKIP=16, VALID_COLS=624, PREFETCH_START=797

Invariants checked:
  - h_count wraps 0..799, v_count wraps 0..524
  - hsync / vsync polarity in correct windows
  - active_video = (h<640) && (v<480)
  - fetch_active = active_video OR (h in [797..799] and v < V_ACTIVE-1)
  - rd_addr == 0 only when NOT fetch_active
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CLK_PERIOD_NS  = 40   # 25 MHz
H_TOTAL        = 800
V_TOTAL        = 525
H_ACTIVE       = 640
V_ACTIVE       = 480
H_SYNC_START   = 656
H_SYNC_END     = 752
V_SYNC_START   = 490
V_SYNC_END     = 492
PREFETCH_START = 797


async def _reset(dut):
    dut.rst.value = 1
    await ClockCycles(dut.clk, 4)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_h_counter_wraps(dut):
    """h_count must never exceed 799 and must reach 799."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    max_h = 0
    for _ in range(H_TOTAL + 10):
        await RisingEdge(dut.clk)
        h = int(dut.h_count.value)
        assert h < H_TOTAL, f"h_count={h} overflowed H_TOTAL={H_TOTAL}"
        if h > max_h:
            max_h = h

    assert max_h == H_TOTAL - 1, f"max h_count={max_h}, expected {H_TOTAL-1}"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_v_counter_wraps(dut):
    """v_count must reach 524 and wrap back to 0 (V_TOTAL=525)."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    max_v = 0
    # Run > 1 full frame
    for _ in range(H_TOTAL * V_TOTAL + H_TOTAL):
        await RisingEdge(dut.clk)
        v = int(dut.v_count.value)
        assert v < V_TOTAL, f"v_count={v} overflowed V_TOTAL={V_TOTAL}"
        if v > max_v:
            max_v = v

    assert max_v == V_TOTAL - 1, f"max v_count={max_v}, expected {V_TOTAL-1}"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_sync_polarity_and_active(dut):
    """
    Run one full frame and verify at every clock:
      - hsync, vsync polarity vs counter windows
      - active_video matches (h<640) && (v<480)
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    errors = []
    for _ in range(H_TOTAL * V_TOTAL):
        await RisingEdge(dut.clk)
        h = int(dut.h_count.value)
        v = int(dut.v_count.value)
        hs = int(dut.hsync.value)
        vs = int(dut.vsync.value)
        av = int(dut.active_video.value)

        exp_hs = 0 if (H_SYNC_START <= h < H_SYNC_END) else 1
        exp_vs = 0 if (V_SYNC_START <= v < V_SYNC_END) else 1
        exp_av = 1 if (h < H_ACTIVE and v < V_ACTIVE) else 0

        if hs != exp_hs:
            errors.append(f"hsync wrong at h={h} v={v}: got {hs} exp {exp_hs}")
        if vs != exp_vs:
            errors.append(f"vsync wrong at h={h} v={v}: got {vs} exp {exp_vs}")
        if av != exp_av:
            errors.append(f"active_video wrong at h={h} v={v}: got {av} exp {exp_av}")

        if len(errors) >= 5:
            break

    assert not errors, "\n".join(errors)


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_fetch_active_and_rd_addr(dut):
    """
    fetch_active must be high inside active region and during h=797..799
    (prefetch window, except last line of frame).
    rd_addr must be 0 when NOT fetch_active.
    """
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    errors = []
    for _ in range(H_TOTAL * V_TOTAL):
        await RisingEdge(dut.clk)
        h  = int(dut.h_count.value)
        v  = int(dut.v_count.value)
        fa = int(dut.fetch_active.value)
        rd = int(dut.rd_addr.value)

        in_active  = (h < H_ACTIVE) and (v < V_ACTIVE)
        in_prefetch = (h >= PREFETCH_START) and (v < V_ACTIVE - 1)
        exp_fa = 1 if (in_active or in_prefetch) else 0

        if fa != exp_fa:
            errors.append(
                f"fetch_active wrong at h={h} v={v}: got {fa} exp {exp_fa}"
            )
        if fa == 0 and rd != 0:
            errors.append(
                f"rd_addr={rd:#x} non-zero when fetch_active=0 at h={h} v={v}"
            )
        if len(errors) >= 5:
            break

    assert not errors, "\n".join(errors)
