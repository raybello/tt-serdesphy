#!/usr/bin/env python3
"""Build the serdesphy UVM testbench with Verilator.

Compiles tb_top (see ../filelist.f) into a Verilated binary using the
verilator build checked out at VERILATOR_BIN_DIR below. Run from
anywhere - paths are resolved relative to this script.
"""

import argparse
import os
import shutil
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
UVM_TB_DIR = os.path.dirname(SCRIPT_DIR)
FILELIST = os.path.join(UVM_TB_DIR, "filelist.f")
BUILD_DIR = os.path.join(UVM_TB_DIR, "build")
VBUILD_DIR = os.path.join(BUILD_DIR, "vbuild")

VERILATOR_BIN_DIR = "/Users/raybello/Github/verilator-verification/third-party/verilator/master/bin"
VERILATOR = os.path.join(VERILATOR_BIN_DIR, "verilator")

TOP_MODULE = "tb_top"
PREFIX = "Vtb"

# Homebrew binutils' `ar` (if it comes first on PATH) writes a GNU-format
# archive that Apple's linker can't read:
#   ld: archive member '/' not a mach-o file in 'Vtb__ALL.a'
# Shim a directory with only Apple's `ar` ahead of it on PATH.
APPLE_AR_SHIM_DIR = "/tmp/apple-ar-shim"
APPLE_AR = "/usr/bin/ar"


def build_env():
    env = os.environ.copy()
    path_entries = [VERILATOR_BIN_DIR]

    if os.path.exists(APPLE_AR):
        os.makedirs(APPLE_AR_SHIM_DIR, exist_ok=True)
        shim = os.path.join(APPLE_AR_SHIM_DIR, "ar")
        if not os.path.islink(shim):
            os.symlink(APPLE_AR, shim)
        path_entries.append(APPLE_AR_SHIM_DIR)

    env["PATH"] = os.pathsep.join(path_entries + [env.get("PATH", "")])
    return env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--clean", action="store_true", help="remove the build directory first")
    parser.add_argument(
        "--no-trace", action="store_true",
        help="build without waveform (VCD) dumping support")
    args = parser.parse_args()

    if not os.path.exists(VERILATOR):
        sys.exit(f"error: verilator binary not found at {VERILATOR}")

    if args.clean and os.path.isdir(BUILD_DIR):
        shutil.rmtree(BUILD_DIR)
    os.makedirs(VBUILD_DIR, exist_ok=True)

    cmd = [
        VERILATOR,
        "--timing",
        "--binary",
        "--build-jobs", "0",
        "-CFLAGS", "-O0",
        "-Wno-fatal",
        "-Wno-UNOPTFLAT",
        "-Wno-BLKANDNBLK",
        "-Wno-context",
        "--top-module", TOP_MODULE,
        "-f", FILELIST,
        "--Mdir", VBUILD_DIR,
        "--prefix", PREFIX,
        "-o", PREFIX,
    ]
    if not args.no_trace:
        cmd.append("--trace")

    print("+ " + " ".join(cmd))
    result = subprocess.run(cmd, cwd=UVM_TB_DIR, env=build_env())
    if result.returncode != 0:
        sys.exit(result.returncode)

    binary = os.path.join(VBUILD_DIR, PREFIX)
    print(f"\nBuild complete: {binary}")


if __name__ == "__main__":
    main()
