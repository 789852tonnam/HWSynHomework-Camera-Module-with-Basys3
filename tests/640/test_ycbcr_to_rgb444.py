"""
cocotb tests for rtl/ycbcr_to_rgb444.v — purely combinational.
No clock; drive inputs, await 1 ns for propagation, read out_rgb444.

LUT (from source):
  r_off  : bin0=-3, bin1=-1, bin2=+1, bin3=+3
  b_off  : bin0=-3, bin1=-1, bin2=+1, bin3=+3
  g_off_cr: bin0=+2, bin1=+1, bin2=-1, bin3=-2
  g_off_cb: bin0=+1, bin1=0,  bin2=0,  bin3=-1
  dither = h_pos ^ v_pos;  y4 = {in_y[2:0], dither}  (4 bits)
  R = clamp(y4 + r_off(in_cr))
  G = clamp(y4 + g_off_cr(in_cr) + g_off_cb(in_cb))
  B = clamp(y4 + b_off(in_cb))
  out_rgb444 = {R[3:0], G[3:0], B[3:0]}
"""

import cocotb
from cocotb.triggers import Timer


def _expected(in_y, in_cb, in_cr, h_pos, v_pos):
    """Python reference model matching ycbcr_to_rgb444.v exactly."""
    dither = h_pos ^ v_pos
    y4 = (in_y << 1) | dither

    r_off    = [-3, -1, +1, +3][in_cr]
    b_off    = [-3, -1, +1, +3][in_cb]
    g_off_cr = [+2, +1, -1, -2][in_cr]
    g_off_cb = [+1,  0,  0, -1][in_cb]
    g_off    = g_off_cr + g_off_cb

    def clamp(x):
        return max(0, min(15, x))

    r = clamp(y4 + r_off)
    g = clamp(y4 + g_off)
    b = clamp(y4 + b_off)
    return (r << 8) | (g << 4) | b


async def _drive(dut, in_y, in_cb, in_cr, h_pos, v_pos):
    dut.in_y.value  = in_y
    dut.in_cb.value = in_cb
    dut.in_cr.value = in_cr
    dut.h_pos.value = h_pos
    dut.v_pos.value = v_pos
    await Timer(1, units='ns')


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_known_values(dut):
    """Spot-check (in_y, in_cb, in_cr, h_pos, v_pos) against reference model."""
    cases = [
        (4, 1, 1, 0, 0),   # mid-gray, no dither  -> R=7  G=9  B=7
        (7, 1, 3, 0, 0),   # bright, strong Cr     -> R=15 G=12 B=13 (R clamps)
        (0, 3, 0, 1, 0),   # dark, strong Cb/Cr swap -> R=0 G=2 B=4
        (7, 2, 2, 1, 1),   # dither cancels (h^v=0)  -> R=15 G=13 B=15
        (3, 1, 1, 0, 0),   # dither=0 case
        (3, 1, 1, 1, 0),   # same ycbcr, dither=1 -> all channels +1
    ]
    for args in cases:
        in_y, in_cb, in_cr, h_pos, v_pos = args
        exp = _expected(*args)
        await _drive(dut, in_y, in_cb, in_cr, h_pos, v_pos)
        got = int(dut.out_rgb444.value)
        assert got == exp, (
            f"in_y={in_y} in_cb={in_cb} in_cr={in_cr} "
            f"h_pos={h_pos} v_pos={v_pos}: "
            f"got=0x{got:03X} expected=0x{exp:03X}"
        )


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_clamp_high(dut):
    """y4 + large positive offset must clamp to 15, not wrap."""
    # in_y=7, dither=0 -> y4=14; r_off(cr=3)=+3 -> 17 > 15, R must clamp to 15
    await _drive(dut, in_y=7, in_cb=1, in_cr=3, h_pos=0, v_pos=0)
    r = (int(dut.out_rgb444.value) >> 8) & 0xF
    assert r == 15, f"R should clamp to 15, got {r}"

    # in_y=7, dither=1 -> y4=15; r_off(cr=3)=+3, b_off(cb=2)=+1 -> both clamp
    await _drive(dut, in_y=7, in_cb=2, in_cr=3, h_pos=0, v_pos=1)
    rgb = int(dut.out_rgb444.value)
    r = (rgb >> 8) & 0xF
    b = rgb & 0xF
    assert r == 15, f"R clamp failed: got {r}"
    assert b == 15, f"B clamp failed: got {b}"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_clamp_low(dut):
    """y4 + large negative offset must clamp to 0, not underflow."""
    # in_y=0, dither=0 -> y4=0; r_off(cr=0)=-3 -> -3 < 0, R must clamp to 0
    await _drive(dut, in_y=0, in_cb=1, in_cr=0, h_pos=0, v_pos=0)
    r = (int(dut.out_rgb444.value) >> 8) & 0xF
    assert r == 0, f"R should clamp to 0, got {r}"

    # in_y=0; b_off(cb=0)=-3 -> -3 < 0, B must clamp to 0
    await _drive(dut, in_y=0, in_cb=0, in_cr=1, h_pos=0, v_pos=0)
    b = int(dut.out_rgb444.value) & 0xF
    assert b == 0, f"B should clamp to 0, got {b}"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_dither_changes_output(dut):
    """Flipping h_pos changes dither, y4 shifts by 1, all non-clamped channels shift."""
    in_y, in_cb, in_cr = 3, 1, 1
    exp0 = _expected(in_y, in_cb, in_cr, 0, 0)   # dither=0
    exp1 = _expected(in_y, in_cb, in_cr, 1, 0)   # dither=1

    await _drive(dut, in_y, in_cb, in_cr, h_pos=0, v_pos=0)
    got0 = int(dut.out_rgb444.value)
    await _drive(dut, in_y, in_cb, in_cr, h_pos=1, v_pos=0)
    got1 = int(dut.out_rgb444.value)

    assert got0 == exp0, f"dither=0: got=0x{got0:03X} exp=0x{exp0:03X}"
    assert got1 == exp1, f"dither=1: got=0x{got1:03X} exp=0x{exp1:03X}"
    assert got0 != got1, "dither had no effect on output"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_all_bins_produce_defined_output(dut):
    """Every combination of (in_cb, in_cr) at mid-luma produces no X bits."""
    in_y = 4
    for in_cr in range(4):
        for in_cb in range(4):
            for h_pos in (0, 1):
                await _drive(dut, in_y, in_cb, in_cr, h_pos=h_pos, v_pos=0)
                raw = dut.out_rgb444.value
                # If any bit is X/Z, int() raises; catch it
                try:
                    val = int(raw)
                    assert 0 <= val <= 0xFFF, f"out of range: 0x{val:X}"
                except ValueError:
                    assert False, (
                        f"out_rgb444 is X/Z for in_y={in_y} in_cb={in_cb} "
                        f"in_cr={in_cr} h_pos={h_pos}"
                    )
