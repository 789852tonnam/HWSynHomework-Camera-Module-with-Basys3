"""
cocotb testbench for sources_1/new/filter_edge.v
Purely combinational: drive inputs, Timer(1ns), check output.
"""

import random
import cocotb
from cocotb.triggers import Timer


# ── reference model ──────────────────────────────────────────────────────────

def _sobel_ref(window, threshold, h_edge, v_edge):
    """Matches filter_edge.v: Gx=right_col-left_col, Gy=bot_row-top_row."""
    (y00, y01, y02), (y10, _y11, y12), (y20, y21, y22) = window
    right_col = y02 + 2 * y12 + y22
    left_col  = y00 + 2 * y10 + y20
    bot_row   = y20 + 2 * y21 + y22
    top_row   = y00 + 2 * y01 + y02
    Gx = right_col - left_col
    Gy = bot_row   - top_row
    mag = abs(Gx) + abs(Gy)
    if h_edge or v_edge:
        return 0x000
    return 0xFFF if mag > threshold else 0x000


async def _drive(dut, window, threshold=1, h_edge=0, v_edge=0):
    (tl, tc, tr), (ml, mc, mr), (bl, bc, br) = window
    dut.top_l.value = tl;  dut.top_c.value = tc;  dut.top_r.value = tr
    dut.mid_l.value = ml;  dut.mid_c.value = mc;  dut.mid_r.value = mr
    dut.bot_l.value = bl;  dut.bot_c.value = bc;  dut.bot_r.value = br
    dut.threshold.value = threshold
    dut.h_edge.value   = h_edge
    dut.v_edge.value   = v_edge
    await Timer(1, unit='ns')


# ── tests ────────────────────────────────────────────────────────────────────

@cocotb.test()
async def test_flat_field_no_edge(dut):
    """Uniform luma -> Gx=0, Gy=0 -> mag=0 -> output 0x000."""
    w = [(4, 4, 4), (4, 4, 4), (4, 4, 4)]
    await _drive(dut, w, threshold=1)
    got = int(dut.out_rgb444.value)
    assert got == 0, f"flat field: got {hex(got)} expected 0x000"


@cocotb.test()
async def test_vertical_step_edge(dut):
    """Left col=0, right col=7 -> strong Gx -> output 0xFFF."""
    w = [(0, 0, 7), (0, 0, 7), (0, 0, 7)]
    await _drive(dut, w, threshold=1)
    exp = _sobel_ref(w, 1, 0, 0)
    got = int(dut.out_rgb444.value)
    assert got == exp == 0xFFF, f"vertical edge: got {hex(got)}"


@cocotb.test()
async def test_horizontal_step_edge(dut):
    """Top row=0, bot row=7 -> strong Gy -> output 0xFFF."""
    w = [(0, 0, 0), (0, 0, 0), (7, 7, 7)]
    await _drive(dut, w, threshold=1)
    exp = _sobel_ref(w, 1, 0, 0)
    got = int(dut.out_rgb444.value)
    assert got == exp == 0xFFF, f"horizontal edge: got {hex(got)}"


@cocotb.test()
async def test_h_edge_forces_black(dut):
    """h_edge=1 -> 0x000 regardless of gradient."""
    w = [(0, 0, 7), (0, 0, 7), (0, 0, 7)]
    await _drive(dut, w, threshold=1, h_edge=1)
    got = int(dut.out_rgb444.value)
    assert got == 0, f"h_edge=1 should force 0x000, got {hex(got)}"


@cocotb.test()
async def test_v_edge_forces_black(dut):
    """v_edge=1 -> 0x000 regardless of gradient."""
    w = [(0, 0, 0), (0, 0, 0), (7, 7, 7)]
    await _drive(dut, w, threshold=1, v_edge=1)
    got = int(dut.out_rgb444.value)
    assert got == 0, f"v_edge=1 should force 0x000, got {hex(got)}"


@cocotb.test()
async def test_below_threshold(dut):
    """Small gradient below threshold -> 0x000."""
    # Gx = 1+2+1 = 4, threshold=15 -> 4 > 15 is False
    w = [(0, 0, 1), (0, 0, 1), (0, 0, 1)]
    await _drive(dut, w, threshold=15)
    exp = _sobel_ref(w, 15, 0, 0)
    got = int(dut.out_rgb444.value)
    assert got == exp == 0, f"below threshold: got {hex(got)}"


@cocotb.test()
async def test_reference_sweep(dut):
    """20 random 3x3 windows compared against Python reference model."""
    rng = random.Random(42)
    for i in range(20):
        w = [(rng.randint(0, 7), rng.randint(0, 7), rng.randint(0, 7))
             for _ in range(3)]
        thresh = rng.randint(0, 15)
        await _drive(dut, w, threshold=thresh)
        exp = _sobel_ref(w, thresh, 0, 0)
        got = int(dut.out_rgb444.value)
        assert got == exp, (
            f"case {i}: window={w} thresh={thresh} "
            f"got {hex(got)} exp {hex(exp)}"
        )
