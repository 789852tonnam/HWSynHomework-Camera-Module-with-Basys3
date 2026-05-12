"""
Python runner for cocotb 2.x tests — 640-path (rtl/).
Invokes iverilog + vvp directly with cocotb's VPI plugin (no make required).

Usage:
    python run_tests.py                    # run all tests
    python run_tests.py cam_capture        # run one module
    python run_tests.py vga_timing filter_pipeline
Requires: cocotb >= 2.0, iverilog + vvp on PATH.

Targets:
    cam_capture, vga_timing, filter_pipeline, frame_buffer,
    sccb_master, ycbcr_to_rgb444
"""

import os
import sys
import pathlib
import subprocess
import cocotb

ROOT      = pathlib.Path(__file__).resolve().parent.parent.parent
RTL       = ROOT / "rtl"
HERE      = pathlib.Path(__file__).resolve().parent
LIBS_DIR  = pathlib.Path(cocotb.__file__).parent / "libs"
VPI_LIB   = "cocotbvpi_icarus"   # loaded via vvp -m

TARGETS = {
    "cam_capture": {
        "toplevel": "cam_capture",
        "sources":  [RTL / "cam_capture.v"],
        "module":   "test_cam_capture",
    },
    "vga_timing": {
        "toplevel": "vga_timing",
        "sources":  [RTL / "vga_timing.v"],
        "module":   "test_vga_timing",
    },
    "filter_pipeline": {
        "toplevel": "filter_pipeline",
        "sources":  [
            RTL / "filter_pipeline.v",
            RTL / "ycbcr_to_rgb444.v",
            RTL / "line_buffer3.v",
            RTL / "filter_edge.v",
        ],
        "module":   "test_filter_pipeline",
    },
    "frame_buffer": {
        "toplevel": "frame_buffer",
        "sources":  [RTL / "frame_buffer.v"],
        "module":   "test_frame_buffer",
    },
    "sccb_master": {
        "toplevel": "sccb_master",
        "sources":  [RTL / "sccb_master.v"],
        "module":   "test_sccb_master",
        "extra_compile_args": ["-P", "sccb_master.HALF_PER_CYCLES=4"],
    },
    "ycbcr_to_rgb444": {
        "toplevel": "ycbcr_to_rgb444",
        "sources":  [RTL / "ycbcr_to_rgb444.v"],
        "module":   "test_ycbcr_to_rgb444",
    },
}


def run(name: str, cfg: dict):
    print(f"\n{'='*60}")
    print(f"  Running: {name}")
    print(f"{'='*60}")

    build_dir = HERE / f"sim_build_{name}"
    build_dir.mkdir(exist_ok=True)
    vvp_out = build_dir / "sim.vvp"

    # 1. Compile
    iverilog_cmd = [
        "iverilog", "-g2012",
        "-o", str(vvp_out),
    ] + cfg.get("extra_compile_args", []) + [str(s) for s in cfg["sources"]]
    print("Compile:", " ".join(iverilog_cmd))
    r = subprocess.run(iverilog_cmd)
    if r.returncode != 0:
        print(f"COMPILE FAILED for {name}")
        sys.exit(r.returncode)

    # 2. Run with cocotb VPI
    import sysconfig
    stdlib = sysconfig.get_path("stdlib")
    platstdlib = sysconfig.get_path("platstdlib")
    purelib = sysconfig.get_path("purelib")

    env = os.environ.copy()
    env["MODULE"]            = cfg["module"]
    env["TOPLEVEL"]          = cfg["toplevel"]
    env["TOPLEVEL_LANG"]     = "verilog"
    env["COCOTB_SIM_NAME"]   = "icarus"
    env["PYGPI_PYTHON_BIN"]  = sys.executable
    env["PYTHONHOME"]        = sys.prefix
    # Build PYTHONPATH: tests dir + stdlib + site-packages
    extra_py = os.pathsep.join(filter(None, [str(HERE), stdlib, platstdlib, purelib,
                                             env.get("PYTHONPATH", "")]))
    env["PYTHONPATH"]        = extra_py
    # cocotb 2.0.1 + Python 3.13 on Windows uses "hon313.dll" instead of "python313.dll"
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
    """Warn if Windows Store Python is detected — it cannot embed correctly in vvp."""
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
