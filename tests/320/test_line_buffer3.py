"""
cocotb testbench for sources_1/new/line_buffer3.v
Uses WIDTH=8 (via -P override) for fast simulation.

Spatial convention (after fix):
  top = (wr+1)%3 = row N-2  (oldest complete)
  mid = (wr-1)%3 = row N-1  (most recent complete)
  bot = wr_idx   = row N    (currently being written; bot_r forwarded from pix_in)

Window columns at h_count h:  col_l=h-2, col_c=h-1, col_r=h (forwarded for bot_r).
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer

WIDTH        = 8          # must match -P line_buffer3.WIDTH=8
CLK_PERIOD   = 40         # ns  (25 MHz)


async def _reset(dut):
    dut.rst.value      = 1
    dut.pix_valid.value = 0
    dut.pix_in.value   = 0
    dut.h_count.value  = 0
    dut.v_count.value  = 0
    await ClockCycles(dut.clk, 4)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


async def _drive_row(dut, luma_list, row_idx):
    """Drive one full row of WIDTH pixels; wr_idx advances at end of line."""
    for col, val in enumerate(luma_list):
        dut.h_count.value   = col
        dut.v_count.value   = row_idx
        dut.pix_in.value    = val
        dut.pix_valid.value = 1
        await RisingEdge(dut.clk)
    dut.pix_valid.value = 0
    await RisingEdge(dut.clk)   # idle cycle after row ends


# ── tests ────────────────────────────────────────────────────────────────────

@cocotb.test()
async def test_reset_clears_outputs(dut):
    """After reset all window outputs are 0 (buffer initialised to 0)."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD, unit='ns').start())
    await _reset(dut)
    await Timer(1, unit='ns')
    for sig in [dut.top_l, dut.top_c, dut.top_r,
                dut.mid_l, dut.mid_c, dut.mid_r,
                dut.bot_l, dut.bot_c, dut.bot_r]:
        assert int(sig.value) == 0, f"{sig._name}={int(sig.value)} after reset, expected 0"


@cocotb.test()
async def test_bot_r_forwarding(dut):
    """bot_r == pix_in one cycle after driving (not stale RAM value)."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD, unit='ns').start())
    await _reset(dut)
    dut.h_count.value   = 3
    dut.v_count.value   = 0
    dut.pix_in.value    = 5
    dut.pix_valid.value = 1
    await RisingEdge(dut.clk)   # output registers latch pix_in -> bot_r
    await Timer(1, unit='ns')
    got = int(dut.bot_r.value)
    assert got == 5, f"bot_r={got} expected 5 (forwarded from pix_in)"
    dut.pix_valid.value = 0


@cocotb.test()
async def test_three_rows_correct_assignment(dut):
    """After 3 rows: top=row0, mid=row1, bot=row2 at interior column."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD, unit='ns').start())
    await _reset(dut)

    # Distinct constant luma per row
    row0 = [1] * WIDTH
    row1 = [3] * WIDTH
    row2 = [5] * WIDTH

    await _drive_row(dut, row0, 0)
    await _drive_row(dut, row1, 1)

    # Drive row2 up to col 4 (interior: h-2,h-1,h all valid)
    for col in range(5):
        dut.h_count.value   = col
        dut.v_count.value   = 2
        dut.pix_in.value    = row2[col]
        dut.pix_valid.value = 1
        await RisingEdge(dut.clk)

    await Timer(1, unit='ns')
    # col_r = 4, col_c = 3, col_l = 2 — all rows have constant value
    assert int(dut.top_r.value) == 1, f"top_r={int(dut.top_r.value)} expected row0=1"
    assert int(dut.mid_r.value) == 3, f"mid_r={int(dut.mid_r.value)} expected row1=3"
    assert int(dut.bot_r.value) == 5, f"bot_r={int(dut.bot_r.value)} expected row2=5 (forwarded)"
    dut.pix_valid.value = 0


@cocotb.test()
async def test_row_wrap_evicts_oldest(dut):
    """After 4 rows: top=row1, mid=row2, bot=row3 (row0 evicted)."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD, unit='ns').start())
    await _reset(dut)

    await _drive_row(dut, [1] * WIDTH, 0)
    await _drive_row(dut, [3] * WIDTH, 1)
    await _drive_row(dut, [5] * WIDTH, 2)

    for col in range(5):
        dut.h_count.value   = col
        dut.v_count.value   = 3
        dut.pix_in.value    = 7
        dut.pix_valid.value = 1
        await RisingEdge(dut.clk)

    await Timer(1, unit='ns')
    assert int(dut.top_r.value) == 3, f"top_r={int(dut.top_r.value)} expected 3 (row1)"
    assert int(dut.mid_r.value) == 5, f"mid_r={int(dut.mid_r.value)} expected 5 (row2)"
    assert int(dut.bot_r.value) == 7, f"bot_r={int(dut.bot_r.value)} expected 7 (row3, forwarded)"
    dut.pix_valid.value = 0


@cocotb.test()
async def test_column_window_left_clamped(dut):
    """At h_count=0: col_l and col_c clamp to 0; all three _l/_c/_r reference col 0."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD, unit='ns').start())
    await _reset(dut)

    # Fill row0 with position-encoded values (0-7 fit in 3 bits for WIDTH=8)
    row0 = [col % 8 for col in range(WIDTH)]      # row0[0]=0, row0[1]=1, ...
    row1 = [(col + 5) % 8 for col in range(WIDTH)] # row1[0]=5, row1[1]=6, ...
    await _drive_row(dut, row0, 0)
    await _drive_row(dut, row1, 1)

    # Drive col=0 of row2
    dut.h_count.value   = 0
    dut.v_count.value   = 2
    dut.pix_in.value    = 7
    dut.pix_valid.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit='ns')

    # col_l = max(0-2,0)=0, col_c = max(0-1,0)=0, col_r = 0  -- all clamp to col 0
    # top_l = top_c = top_r = row0[0] = 0
    # mid_l = mid_c = mid_r = row1[0] = 5
    assert int(dut.top_l.value) == 0 and int(dut.top_c.value) == 0 and int(dut.top_r.value) == 0, \
        f"top clamped wrong: l={int(dut.top_l.value)} c={int(dut.top_c.value)} r={int(dut.top_r.value)}"
    assert int(dut.mid_l.value) == 5 and int(dut.mid_c.value) == 5 and int(dut.mid_r.value) == 5, \
        f"mid clamped wrong: l={int(dut.mid_l.value)} c={int(dut.mid_c.value)} r={int(dut.mid_r.value)}"
    dut.pix_valid.value = 0
