"""
Python runner for cocotb 2.x tests — 320-path (sources_1/new/).
Invokes iverilog + vvp directly with cocotb's VPI plugin (no make required).

Usage:
    python run_tests.py                    # run all tests
    python run_tests.py camera_capture     # run one module
Requires: cocotb >= 2.0, iverilog + vvp on PATH.

Targets: camera_capture, vga_display, frame_buffer, sccb_config, line_buffer3, filter_edge
"""

import os
import sys
import pathlib
import subprocess
import sysconfig
import cocotb

ROOT      = pathlib.Path(__file__).resolve().parent.parent.parent
SRC       = ROOT / "sources_1" / "new"
HERE      = pathlib.Path(__file__).resolve().parent
LIBS_DIR  = pathlib.Path(cocotb.__file__).parent / "libs"
VPI_LIB   = "cocotbvpi_icarus"

TARGETS = {
    "camera_capture": {
        "toplevel": "camera_capture_640x320",
        "sources":  [SRC / "camera_capture_640x320.v"],
        "module":   "test_camera_capture",
    },
    "vga_display": {
        "toplevel": "vga_640x320_display",
        "sources":  [SRC / "vga_640x320_display.v"],
        "module":   "test_vga_display",
    },
    "frame_buffer": {
        "toplevel": "frame_buffer_640x320",
        "sources":  [SRC / "frame_buffer_640x320.v"],
        "module":   "test_frame_buffer",
    },
    "sccb_config": {
        "toplevel": "sccb_config",
        "sources":  [SRC / "sccb_config.v"],
        "module":   "test_sccb_config",
    },
    "line_buffer3": {
        "toplevel": "line_buffer3",
        "sources":  [SRC / "line_buffer3.v"],
        "module":   "test_line_buffer3",
        "extra_compile_args": ["-P", "line_buffer3.WIDTH=8"],
    },
    "filter_edge": {
        "toplevel": "filter_edge",
        "sources":  [SRC / "filter_edge.v"],
        "module":   "test_filter_edge",
    },
}


def _write_dump_v(build_dir: pathlib.Path, toplevel: str) -> pathlib.Path:
    """Generate a Verilog dump module that writes a VCD waveform file."""
    vcd_path = (build_dir / "dump.vcd").as_posix()
    dump_v   = build_dir / "dump.v"
    dump_v.write_text(
        f'`timescale 1ns/1ps\n'
        f'module dump;\n'
        f'  initial begin\n'
        f'    $dumpfile("{vcd_path}");\n'
        f'    $dumpvars(0, {toplevel});\n'
        f'  end\n'
        f'endmodule\n'
    )
    return dump_v


def run(name: str, cfg: dict):
    print(f"\n{'='*60}")
    print(f"  Running: {name}")
    print(f"{'='*60}")

    build_dir = HERE / f"sim_build_{name}"
    build_dir.mkdir(exist_ok=True)
    vvp_out = build_dir / "sim.vvp"

    dump_v = _write_dump_v(build_dir, cfg["toplevel"])

    iverilog_cmd = [
        "iverilog", "-g2012",
        "-o", str(vvp_out),
    ] + cfg.get("extra_compile_args", []) + [str(s) for s in cfg["sources"]] + [str(dump_v)]
    print("Compile:", " ".join(iverilog_cmd))
    r = subprocess.run(iverilog_cmd)
    if r.returncode != 0:
        print(f"COMPILE FAILED for {name}")
        sys.exit(r.returncode)

    stdlib     = sysconfig.get_path("stdlib")
    platstdlib = sysconfig.get_path("platstdlib")
    purelib    = sysconfig.get_path("purelib")

    env = os.environ.copy()
    env["COCOTB_TEST_MODULES"] = cfg["module"]
    env["COCOTB_TOPLEVEL"]     = cfg["toplevel"]
    env["TOPLEVEL_LANG"]       = "verilog"
    env["COCOTB_SIM_NAME"]     = "icarus"
    env["PYGPI_PYTHON_BIN"]    = sys.executable
    env["PYTHONHOME"]          = sys.prefix
    env["PYTHONPATH"]          = os.pathsep.join(filter(None, [
        str(HERE), stdlib, platstdlib, purelib, env.get("PYTHONPATH", "")
    ]))
    # LIBS_DIR first (cocotbvpi_icarus.vpl), then Python home (hon313.dll deps)
    env["PATH"]                = os.pathsep.join([str(LIBS_DIR), sys.prefix, env.get("PATH", "")])

    vvp_cmd = [
        "vvp",
        "-M", str(LIBS_DIR),
        "-m", VPI_LIB,
        str(vvp_out),
    ]
    print("Simulate:", " ".join(vvp_cmd))
    r = subprocess.run(vvp_cmd, env=env)
    if r.returncode != 0:
        print(f"SIMULATION FAILED for {name}")
        sys.exit(r.returncode)


_FALLBACK_PYTHONS = [
    r"C:\Users\78985\miniconda3\python.exe",
    r"C:\Users\78985\anaconda3\python.exe",
    r"C:\Python313\python.exe",
    r"C:\Python312\python.exe",
    r"C:\Python311\python.exe",
    r"C:\Program Files\Python313\python.exe",
    r"C:\Program Files\Python312\python.exe",
]


def _check_python():
    """Re-exec with a non-Store Python if Windows Store Python is detected."""
    if "WindowsApps" not in sys.executable and \
       "AppData\\Local\\Microsoft" not in sys.executable:
        return  # already a real Python

    for candidate in _FALLBACK_PYTHONS:
        if pathlib.Path(candidate).exists():
            print(f"Windows Store Python detected — re-executing with {candidate}", file=sys.stderr)
            os.execv(candidate, [candidate] + sys.argv)
            # os.execv replaces the process; nothing below runs if successful

    print("ERROR: Windows Store Python detected and no fallback Python found.", file=sys.stderr)
    print("  Install Python from https://www.python.org/downloads/", file=sys.stderr)
    print("  or activate a conda environment before running.", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    _check_python()
    requested = sys.argv[1:] if len(sys.argv) > 1 else list(TARGETS)
    for key in requested:
        if key not in TARGETS:
            print(f"Unknown target '{key}'. Valid: {list(TARGETS)}", file=sys.stderr)
            sys.exit(1)
    for key in requested:
        run(key, TARGETS[key])
    print("\nAll requested tests completed.")
