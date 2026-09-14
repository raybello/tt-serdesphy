#!/usr/bin/env python3
"""Build the serdesphy UVM testbench with Verilator.

Compiles tb_top (see ../filelist.f) into a Verilated binary. Run from
anywhere - paths are resolved relative to this script.

The executable is written to build/<build-name>/<build-name> (default
build name: "tt_serdesphy"), so multiple named builds can coexist - see -b.

Verilator is resolved from $SERDESPHY_VERILATOR if set, else looked up
on PATH. (Not $VERILATOR_BIN - that name is reserved by verilator's own
bin/verilator wrapper script, which reads it to decide which binary to
re-exec; pointing it at the wrapper's own path makes it exec itself and
fail with "re-entered N levels deep via $VERILATOR_RUNNING".) The
checked-in filelist.f/test_harness/filelist.f use @@REPO_ROOT@@ and
@@UVM_SRC_DIR@@ placeholder tokens instead of hardcoded absolute paths;
this script resolves them (recursively, for nested `-f` files) into a
real filelist under the build directory before invoking Verilator.
REPO_ROOT defaults to $REPO_PATH if set, else this script's own
location; UVM_SRC_DIR defaults to $REPO_ROOT/third_party/uvm/src (see
.gitmodules) and can be overridden with $UVM_SRC_DIR for local
checkouts elsewhere. `source bootenv` (repo root) sets REPO_PATH/
SERDESPHY_VERILATOR to sane defaults if they aren't already set.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
UVM_TB_DIR = os.path.dirname(SCRIPT_DIR)
REPO_ROOT = os.environ.get("REPO_PATH", os.path.dirname(UVM_TB_DIR))
FILELIST = os.path.join(UVM_TB_DIR, "filelist.f")
BUILD_DIR = os.path.join(UVM_TB_DIR, "build")

UVM_SRC_DIR = os.environ.get(
    "UVM_SRC_DIR", os.path.join(REPO_ROOT, "third_party", "uvm", "src"))

TOP_MODULE = "tb_top"
# Not "default" - that becomes the Verilated model's C++ class name via
# --prefix, and "default" is a reserved C++ keyword (breaks with errors
# like "declaration of anonymous class must be a definition").
DEFAULT_BUILD_NAME = "tt_serdesphy"

FILELIST_TOKENS = {
    "@@REPO_ROOT@@": REPO_ROOT,
    "@@UVM_SRC_DIR@@": UVM_SRC_DIR,
}

NESTED_F_RE = re.compile(r"^-f\s+(\S+)\s*$")

# Homebrew binutils' `ar` (if it comes first on PATH) writes a GNU-format
# archive that Apple's linker can't read:
#   ld: archive member '/' not a mach-o file in 'Vtb__ALL.a'
# Shim a directory with only Apple's `ar` ahead of it on PATH.
APPLE_AR_SHIM_DIR = "/tmp/apple-ar-shim"
APPLE_AR = "/usr/bin/ar"


def find_verilator():
    override = os.environ.get("SERDESPHY_VERILATOR")
    if override:
        return override
    found = shutil.which("verilator")
    if found:
        return found
    sys.exit(
        "error: verilator not found on PATH and $SERDESPHY_VERILATOR not set")


# Reserved by verilator's own bin/verilator wrapper script (it reads
# these to decide which binary to re-exec / how to run under gdb or
# valgrind). Never let one of these leak in already set to something
# that resolves back to the wrapper itself, or verilator recurses into
# itself and fails with "re-entered N levels deep via $VERILATOR_RUNNING".
VERILATOR_RESERVED_ENV_VARS = [
    "VERILATOR_BIN", "VERILATOR_ROOT", "VERILATOR_GDB", "VERILATOR_VALGRIND",
    "VERILATOR_RUNNING",
]


def build_env():
    env = os.environ.copy()
    for var in VERILATOR_RESERVED_ENV_VARS:
        env.pop(var, None)
    path_entries = []

    if os.path.exists(APPLE_AR):
        os.makedirs(APPLE_AR_SHIM_DIR, exist_ok=True)
        shim = os.path.join(APPLE_AR_SHIM_DIR, "ar")
        if not os.path.islink(shim):
            os.symlink(APPLE_AR, shim)
        path_entries.append(APPLE_AR_SHIM_DIR)

    env["PATH"] = os.pathsep.join(path_entries + [env.get("PATH", "")])
    return env


def resolve_filelist(src_path, out_dir, seen=None):
    """Substitutes FILELIST_TOKENS into src_path, recursively resolving
    any nested `-f <path>` line, and writes the result(s) under out_dir,
    mirroring each file's path relative to REPO_ROOT (so e.g. both
    uvm_tb/filelist.f and uvm_tb/test_harness/filelist.f - which share a
    basename - get distinct output paths instead of colliding). Returns
    the resolved path for src_path."""
    seen = seen if seen is not None else {}
    if src_path in seen:
        return seen[src_path]

    with open(src_path) as f:
        lines = f.readlines()

    resolved_lines = []
    for line in lines:
        for token, value in FILELIST_TOKENS.items():
            line = line.replace(token, value)

        match = NESTED_F_RE.match(line.strip())
        if match:
            nested_src = match.group(1)
            nested_out = resolve_filelist(nested_src, out_dir, seen)
            line = f"-f {nested_out}\n"

        resolved_lines.append(line)

    rel_path = os.path.relpath(src_path, REPO_ROOT)
    out_path = os.path.join(out_dir, rel_path)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as f:
        f.writelines(resolved_lines)

    seen[src_path] = out_path
    return out_path


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "-b", "--build-name", default=DEFAULT_BUILD_NAME,
        help=f"name for this build; output goes to build/<name>/<name> "
             f"(default: {DEFAULT_BUILD_NAME})")
    parser.add_argument(
        "-o", "--option", action="append", default=[], metavar="FLAG",
        help="extra flag passed through to verilator (repeatable), e.g. "
             "-o +define+FOO or --option=-Wno-context")
    parser.add_argument(
        "--clean", action="store_true", help="remove the build directory first")
    parser.add_argument(
        "--no-trace", action="store_true",
        help="build without waveform (VCD) dumping support")
    args = parser.parse_args()

    verilator = find_verilator()

    build_name = args.build_name
    vbuild_dir = os.path.join(BUILD_DIR, build_name)
    prefix = build_name

    if args.clean and os.path.isdir(vbuild_dir):
        shutil.rmtree(vbuild_dir)
    os.makedirs(vbuild_dir, exist_ok=True)

    resolved_filelist = resolve_filelist(FILELIST, vbuild_dir)

    cmd = [
        verilator,
        "--timing",
        "--binary",
        "--build-jobs", "0",
        "-CFLAGS", "-O0",
        "-Wno-fatal",
        "-Wno-UNOPTFLAT",
        "-Wno-BLKANDNBLK",
        "-Wno-context",
        "--top-module", TOP_MODULE,
        "-f", resolved_filelist,
        "--Mdir", vbuild_dir,
        "--prefix", prefix,
        "-o", prefix,
    ]
    if not args.no_trace:
        cmd.append("--trace")
    cmd.extend(args.option)

    print("+ " + " ".join(cmd))
    result = subprocess.run(cmd, cwd=UVM_TB_DIR, env=build_env())
    if result.returncode != 0:
        sys.exit(result.returncode)

    binary = os.path.join(vbuild_dir, prefix)
    print(f"\nBuild complete: {binary}")


if __name__ == "__main__":
    main()
