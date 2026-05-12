"""
cocotb tests for sources_1/new/sccb_config.v — self-starting 8-register SCCB init.
No reset, no start/done ports; module runs automatically after power-on.

Clock hierarchy:
  clk (25 MHz) -> clk_div counts 0..31 -> i2c_clk toggles (period = 64 clk cycles)
  State machine runs on posedge i2c_clk.

Timing budget (at 25 MHz):
  Each state = 1 i2c_clk cycle = 64 clk cycles.
  Per register ≈ 122 i2c_clk states = 7808 clk cycles.
  Post-reset delay (reg_idx==1): 400 i2c_clk cycles = 25600 clk cycles.
  Total for 8 registers ≈ 120000 clk cycles (TOTAL_CLOCKS).

After all 8 registers: reg_idx=8 >= TOTAL_REGS=8 -> state machine stays idle.
sioc_reg remains 1 (left by last STOP condition).

Open-drain SDA model:
  siod = 0 when (siod_out_en && siod_reg==0), else 1'bz.
  No slave -> siod is 1'bz most of the time.
  Reading 1'bz as int() raises ValueError; catch it and treat as 1 (pulled-up).
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CLK_PERIOD_NS = 40         # 25 MHz
TOTAL_CLOCKS  = 120_000    # budget for all 8 registers to complete


def _read_siod(dut):
    """Return 0 if siod is driven low, 1 if released (Z = pulled-up)."""
    try:
        return int(dut.siod.value)
    except ValueError:
        return 1


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_sioc_not_stuck_high(dut):
    """sioc must go low within 200 clk cycles — verifies i2c_clk gen and FSM start."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await ClockCycles(dut.clk, 4)

    saw_low = False
    for _ in range(200):
        await RisingEdge(dut.clk)
        if int(dut.sioc.value) == 0:
            saw_low = True
            break

    assert saw_low, "sioc never went low in 200 cycles — i2c_clk gen or FSM broken"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_start_condition_occurs(dut):
    """Detect at least one SCCB START condition: siod=0 while sioc=1."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await ClockCycles(dut.clk, 4)

    # START visible ~cycle 97-159 (state 1 pulls SDA low while SCL=1)
    found = False
    for _ in range(1000):
        await RisingEdge(dut.clk)
        sioc_v = int(dut.sioc.value)
        siod_v = _read_siod(dut)

        if sioc_v == 1 and siod_v == 0:
            found = True
            break

    assert found, "No SCCB START condition (siod=0 while sioc=1) in first 1000 cycles"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_stop_condition_occurs(dut):
    """Detect at least one SCCB STOP condition: siod rises to 1 while sioc=1."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await ClockCycles(dut.clk, 4)

    prev_siod = 1
    found = False
    for _ in range(20_000):   # enough for first register to complete
        await RisingEdge(dut.clk)
        sioc_v = int(dut.sioc.value)
        siod_v = _read_siod(dut)

        # STOP: siod rises (0 -> 1) while sioc=1
        if sioc_v == 1 and prev_siod == 0 and siod_v == 1:
            found = True
            break
        prev_siod = siod_v

    assert found, "No SCCB STOP condition detected within 20000 cycles"


# ---------------------------------------------------------------------------
@cocotb.test()
async def test_all_registers_sent(dut):
    """After TOTAL_CLOCKS, sioc stabilizes high — all 8 registers were transmitted."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, units="ns").start())
    await ClockCycles(dut.clk, TOTAL_CLOCKS)

    # If module is idle (reg_idx>=8), sioc stays 1 indefinitely
    for _ in range(300):
        await RisingEdge(dut.clk)
        assert int(dut.sioc.value) == 1, (
            "sioc still toggling after TOTAL_CLOCKS — not all 8 registers sent"
        )
