"""
cocotb tests for rtl/sccb_master.v — SCCB 3-byte write master.
Compiled with HALF_PER_CYCLES=4 (via -P flag) to speed up simulation.

Protocol: START | ID(8) | DC | SUB(8) | DC | DATA(8) | DC | STOP
DRIVE_MASK = 27'b111111110_111111110_111111110 — DC slots are released.
ACK sampled at midpoint of HIGH phase: bit_idx 18 (ID), 9 (sub), 0 (data).
Without a slave, SDA floats (1'bz) during DC slots -> ack_* stays 1'b1.

With HALF_PER_CYCLES=4:
  S_START   = 4 cycles
  Each bit  = S_LOW(4) + S_HIGH(4) = 8 cycles; 27 bits = 216 cycles
  S_STOP_A/B/C = 4+4+4 = 12 cycles
  Total     ≈ 232 cycles per transaction.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CLK_PERIOD_NS = 40    # 25 MHz
HALF_PER      = 4     # must match -P sccb_master.HALF_PER_CYCLES=4
TX_CYCLES     = 4 + 27 * 2 * HALF_PER + 3 * HALF_PER + 20   # ≈ 252, generous


async def _reset(dut):
    dut.rst.value      = 1
    dut.start.value    = 0
    dut.id.value       = 0
    dut.sub_addr.value = 0
    dut.data.value     = 0
    await ClockCycles(dut.clk, 4)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)


async def _send(dut, id_byte=0x42, sub=0x12, data=0xAB):
    """Pulse start for one clock cycle; caller then monitors done."""
    dut.id.value       = id_byte
    dut.sub_addr.value = sub
    dut.data.value     = data
    dut.start.value    = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0


async def _wait_done(dut, timeout=400):
    """Poll for done=1; return cycle count. Assert on timeout."""
    for i in range(timeout):
        await RisingEdge(dut.clk)
        if int(dut.done.value) == 1:
            return i
    assert False, f"done never asserted within {timeout} cycles"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_idle_state(dut):
    """After reset: busy=0, done=0."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await _reset(dut)

    assert int(dut.busy.value) == 0, "busy should be 0 at idle"
    assert int(dut.done.value) == 0, "done should be 0 at idle"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_busy_rises_and_done_pulses(dut):
    """start -> busy=1; done pulses exactly once; busy falls after done."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await _reset(dut)

    await _send(dut, id_byte=0x42, sub=0x11, data=0x01)
    # busy becomes 1 on the edge inside _send
    assert int(dut.busy.value) == 1, "busy must rise on start"

    cycles = await _wait_done(dut, timeout=350)
    assert cycles < 280, f"transaction too slow: {cycles} cycles (expected < 280)"

    # done is 1 now; one clock later busy must be 0 and done 0
    await RisingEdge(dut.clk)
    assert int(dut.busy.value) == 0, "busy must fall one cycle after done"
    assert int(dut.done.value) == 0, "done must be 0 the cycle after it fired"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_done_one_cycle_only(dut):
    """done must stay 1 for exactly one clock cycle."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await _reset(dut)

    await _send(dut, id_byte=0x42, sub=0x12, data=0xAB)
    await _wait_done(dut, timeout=350)

    for _ in range(4):
        await RisingEdge(dut.clk)
        assert int(dut.done.value) == 0, "done must be 0 after its single-cycle pulse"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_start_ignored_while_busy(dut):
    """A second start during busy is ignored; only one done pulse results."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await _reset(dut)

    await _send(dut, id_byte=0x42, sub=0x11, data=0x01)

    # Pulse start again while still busy
    await ClockCycles(dut.clk, 5)
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0

    done_count = 0
    for _ in range(600):
        await RisingEdge(dut.clk)
        if int(dut.done.value) == 1:
            done_count += 1

    assert done_count == 1, f"expected 1 done pulse, got {done_count}"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_reset_clears_busy(dut):
    """rst=1 mid-transaction clears busy and done immediately."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await _reset(dut)

    await _send(dut, id_byte=0x42, sub=0x11, data=0x01)
    await ClockCycles(dut.clk, 10)    # mid-transaction

    dut.rst.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert int(dut.busy.value) == 0, "rst must clear busy"
    assert int(dut.done.value) == 0, "rst must clear done"
    dut.rst.value = 0


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_ack_fields_after_no_slave(dut):
    """With no slave on the bus, SDA floats high during DC slots -> ack_* = 1."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await _reset(dut)

    await _send(dut, id_byte=0x42, sub=0x3A, data=0x04)
    await _wait_done(dut, timeout=350)

    assert int(dut.ack_id.value)   == 1, "ack_id should be 1 (no slave)"
    assert int(dut.ack_sub.value)  == 1, "ack_sub should be 1 (no slave)"
    assert int(dut.ack_data.value) == 1, "ack_data should be 1 (no slave)"
