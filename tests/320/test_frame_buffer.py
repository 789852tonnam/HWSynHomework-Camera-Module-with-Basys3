"""
cocotb tests for sources_1/new/frame_buffer_640x320.v (320-path RGB444 BRAM).

Geometry:
  76,800 entries × 12 bits (one RGB444 per 320×240 pixel)
  Dual-clock: wr at clk_w, rd at clk_r; 1-cycle synchronous BRAM latency.

Invariants checked:
  - Write then read-back at several addresses (corners, random interior)
  - we=0 does NOT overwrite an existing value
  - Last address (76799) is accessible
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, FallingEdge

CLK_PERIOD_NS = 10   # use same clock for both ports (avoids CDC complexity)
LAST_ADDR     = 76_799


async def _write(dut, addr: int, data: int):
    """Write data to addr with we=1 for one cycle, then deassert."""
    dut.addr_w.value = addr
    dut.din.value    = data
    dut.we.value     = 1
    await RisingEdge(dut.clk_w)
    dut.we.value = 0
    await RisingEdge(dut.clk_w)   # deassert settles


async def _read(dut, addr: int) -> int:
    """Read from addr; 1-cycle BRAM latency -> sample after NBA commits.
    FallingEdge escapes the caller's active posedge timestep so we don't
    race against clk_w. Second FallingEdge waits until NBA commits dout."""
    dut.addr_r.value = addr
    await FallingEdge(dut.clk_r)  # escape caller's posedge timestep
    await RisingEdge(dut.clk_r)   # BRAM latches addr_r -> dout <= mem[addr]
    await FallingEdge(dut.clk_r)  # NBA committed; active region (driveable)
    return int(dut.dout.value)


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_write_readback(dut):
    """Write distinct values to several addresses; verify read-back."""
    cocotb.start_soon(Clock(dut.clk_w, CLK_PERIOD_NS, unit="ns").start())
    cocotb.start_soon(Clock(dut.clk_r, CLK_PERIOD_NS, unit="ns").start())

    dut.we.value     = 0
    dut.addr_w.value = 0
    dut.din.value    = 0
    dut.addr_r.value = 0
    await ClockCycles(dut.clk_w, 2)

    cases = [
        (0,         0xABC),
        (1,         0x123),
        (319,       0xFFF),   # last col of row 0
        (320,       0xDEF),   # first col of row 1
        (LAST_ADDR, 0x555),
    ]

    for addr, data in cases:
        await _write(dut, addr, data)

    for addr, exp in cases:
        got = await _read(dut, addr)
        assert got == exp, (
            f"addr={addr}: got={got:#05x} expected={exp:#05x}"
        )


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_we_gate(dut):
    """we=0 must not overwrite an existing value."""
    cocotb.start_soon(Clock(dut.clk_w, CLK_PERIOD_NS, unit="ns").start())
    cocotb.start_soon(Clock(dut.clk_r, CLK_PERIOD_NS, unit="ns").start())

    dut.we.value     = 0
    dut.addr_w.value = 0
    dut.addr_r.value = 0
    dut.din.value    = 0
    await ClockCycles(dut.clk_w, 2)

    # Write known value
    await _write(dut, 100, 0xCAFE & 0xFFF)

    # Attempt overwrite with we=0 (should be ignored)
    dut.addr_w.value = 100
    dut.din.value    = 0x000
    dut.we.value     = 0
    await RisingEdge(dut.clk_w)

    got = await _read(dut, 100)
    assert got == (0xCAFE & 0xFFF), (
        f"we=0 overwrote address 100: got={got:#05x}"
    )


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_last_address_accessible(dut):
    """Address 76799 (last pixel) must be writable and readable."""
    cocotb.start_soon(Clock(dut.clk_w, CLK_PERIOD_NS, unit="ns").start())
    cocotb.start_soon(Clock(dut.clk_r, CLK_PERIOD_NS, unit="ns").start())

    dut.we.value     = 0
    dut.addr_w.value = 0
    dut.addr_r.value = 0
    dut.din.value    = 0
    await ClockCycles(dut.clk_w, 2)

    await _write(dut, LAST_ADDR, 0x7E7)
    got = await _read(dut, LAST_ADDR)
    assert got == 0x7E7, (
        f"last addr {LAST_ADDR}: got={got:#05x} expected=0x7e7"
    )
