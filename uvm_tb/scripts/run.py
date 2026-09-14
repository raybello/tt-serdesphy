#!/usr/bin/env python3
"""Run the compiled serdesphy UVM testbench.

Each invocation gets its own directory under ../sim/<test>_<seed>/,
holding that run's log (sim.log) and waveform (waves.vcd, if the
binary was built with tracing - see build.py). A random seed is
picked unless --seed/-s is given, so reruns are reproducible on
request but distinct by default.

Usage:
    ./run.py                       # runs basic_test with a random seed
    ./run.py -t reset_test         # runs a specific test
    ./run.py -t clk_test -s 12345  # runs with a fixed seed
"""

import argparse
import os
import random
import re
import subprocess
import sys

# Matches the counts UVM's report summary prints at the end of a run,
# e.g. "UVM_ERROR :    2" / "UVM_FATAL :    0".
SEVERITY_COUNT_RE = re.compile(r"^UVM_(ERROR|FATAL)\s*:\s*(\d+)\s*$")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
UVM_TB_DIR = os.path.dirname(SCRIPT_DIR)
BUILD_DIR = os.path.join(UVM_TB_DIR, "build")
SIM_DIR = os.path.join(UVM_TB_DIR, "sim")

DEFAULT_TEST = "basic_test"
DEFAULT_BUILD_NAME = "tt_serdesphy"  # must match build.py's DEFAULT_BUILD_NAME
MAX_SEED = 2**31 - 1


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "-t", "--test", default=DEFAULT_TEST,
        help=f"UVM_TESTNAME to run (default: {DEFAULT_TEST})")
    parser.add_argument(
        "-s", "--seed", type=int, default=None,
        help="random seed (default: a freshly generated one)")
    parser.add_argument(
        "-b", "--build-name", default=DEFAULT_BUILD_NAME,
        help=f"name of the build to run against, as built by build.py -b "
             f"(default: {DEFAULT_BUILD_NAME})")
    parser.add_argument(
        "-o", "--option", action="append", default=[], metavar="FLAG",
        help="extra flag passed through to the simulation binary "
             "(repeatable), e.g. -o +MY_PLUSARG=1. Must be given before "
             "any bare positional extra args.")
    parser.add_argument(
        "extra", nargs=argparse.REMAINDER,
        help="extra +args/-args passed through to the simulation binary")
    args = parser.parse_args()

    binary = os.path.join(BUILD_DIR, args.build_name, args.build_name)
    if not os.path.exists(binary):
        sys.exit(f"error: simulation binary not found at {binary}\n"
                  f"       run build.py -b {args.build_name} first")

    seed = args.seed if args.seed is not None else random.randint(1, MAX_SEED)

    run_dir = os.path.join(SIM_DIR, f"{args.test}_{seed}")
    os.makedirs(run_dir, exist_ok=True)
    log_path = os.path.join(run_dir, "sim.log")

    cmd = ([binary, f"+UVM_TESTNAME={args.test}", f"+verilator+seed+{seed}",
            "+UVM_NO_RELNOTES"] + args.option + args.extra)
    print("+ " + " ".join(cmd))
    print(f"  run dir: {run_dir}")

    with open(log_path, "w") as log_file:
        process = subprocess.Popen(
            cmd, cwd=run_dir, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1)
        for line in process.stdout:
            sys.stdout.write(line)
            log_file.write(line)
        process.wait()

    print(f"\nLog: {log_path}")
    waves = os.path.join(run_dir, "waves.vcd")
    if os.path.exists(waves):
        print(f"Waves: {waves}")

    passed = process.returncode == 0 and pass_fail(log_path)
    verdict = f"{'TEST PASSED' if passed else 'TEST FAILED'}: {args.test}"
    print(f"\n{verdict}")
    with open(log_path, "a") as log_file:
        log_file.write(f"\n{verdict}\n")

    sys.exit(0 if passed else 1)


def pass_fail(log_path):
    """Post-processes a completed sim.log: pass iff UVM's report summary
    shows zero UVM_ERROR and zero UVM_FATAL. Missing counts (e.g. the
    binary crashed before printing a summary) are treated as a failure."""
    error_fatal_count = 0
    found_summary = False
    with open(log_path) as log_file:
        for line in log_file:
            match = SEVERITY_COUNT_RE.match(line.strip())
            if match:
                found_summary = True
                error_fatal_count += int(match.group(2))
    return found_summary and error_fatal_count == 0


if __name__ == "__main__":
    main()
