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


def run(name: str, cfg: dict):
    print(f"\n{'='*60}")
    print(f"  Running: {name}")
    print(f"{'='*60}")

    build_dir = HERE / f"sim_build_{name}"
    build_dir.mkdir(exist_ok=True)
    vvp_out = build_dir / "sim.vvp"

    iverilog_cmd = [
        "iverilog", "-g2012",
        "-o", str(vvp_out),
    ] + cfg.get("extra_compile_args", []) + [str(s) for s in cfg["sources"]]
    print("Compile:", " ".join(iverilog_cmd))
    r = subprocess.run(iverilog_cmd)
    if r.returncode != 0:
        print(f"COMPILE FAILED for {name}")
        sys.exit(r.returncode)

    env = os.environ.copy()
    env["MODULE"]            = cfg["module"]
    env["TOPLEVEL"]          = cfg["toplevel"]
    env["TOPLEVEL_LANG"]     = "verilog"
    env["COCOTB_SIM_NAME"]   = "icarus"
    env["PYTHONPATH"]        = str(HERE) + os.pathsep + env.get("PYTHONPATH", "")
    env["PYGPI_PYTHON_BIN"]  = sys.executable
    env["PATH"]              = str(LIBS_DIR) + os.pathsep + env.get("PATH", "")

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


def _check_python():
    if "WindowsApps" in sys.executable or "AppData\\Local\\Microsoft" in sys.executable:
        print("WARNING: Windows Store Python detected.", file=sys.stderr)
        print("  cocotb embedding fails in vvp due to AppContainer DLL restrictions.", file=sys.stderr)
        print("  Install Python from https://www.python.org/downloads/ and re-run.", file=sys.stderr)
        print("  Or use WSL where the tests work without modification.", file=sys.stderr)
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
