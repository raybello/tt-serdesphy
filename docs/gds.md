# GDS Build Documentation

## Overview

This document describes how to build a GDS (GDSII stream-out) file from the serdesphy project
locally, replicating the `.github/workflows/gds.yaml` GitHub Action workflow.

## Prerequisites

### System Dependencies

The following system packages are required:

```bash
# Build tools
apt-get install -y cmake build-essential libeigen3-dev swig \
  python3-dev libboost-all-dev libreadline-dev tcl-dev tk-dev \
  openjdk-21-jdk-headless git

# GDSII tools
apt-get install -y klayout

# Linting
apt-get install -y verilator

# Utility scripts
apt-get install -y librsvg2-bin pngquant  # for PNG rendering
```

### OpenROAD (Built from Source)

OpenROAD must be built from source as pre-built ARM64 binaries are not available:

```bash
cd /workspace
git clone --depth 1 https://github.com/The-OpenROAD-Project/OpenROAD.git openroad-src
cd openroad-src && mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DENABLE_GUI=OFF -DCMAKE_INSTALL_PREFIX=/usr/local ..
make -j$(nproc)
make install
```

### LibreLane 3.0.0

```bash
python3 -m venv actions/gds/venv
source actions/gds/venv/bin/activate
pip install librelane==3.0.0
```

## PDK Setup

The IHP sg13g2 PDK is automatically downloaded by LibreLane's `ciel` PDK manager
when running with `--ihp`. The PDK is cached at:

```
<cel_dir>/ciel/ihp-sg13g2/versions/<hash>/
```

## Build Steps

### 1. Checkout tt-support-tools

```bash
cd actions
svn checkout https://github.com/TinyTapeout/tt-support-tools/trunk tt
```

### 2. Create Symlink

```bash
ln -sf actions/fpga/tt tt
```

### 3. Install tt-support-tools Dependencies

```bash
pip install -r actions/fpga/tt/requirements.txt
```

### 4. Create User Config

```bash
export PATH="$(pwd)/actions/gds/venv/bin:$PATH"
python tt/tt_tool.py --create-user-config --ihp
```

### 5. Run Harden (Full GDS Flow)

```bash
export PATH="$(pwd)/actions/gds/venv/bin:$PATH"
export LINTER_DEFINES="SYNTHESIS"
python tt/tt_tool.py --harden --ihp --no-docker
```

## Workarounds for Native (Non-Docker) Builds

### Verilator Lint on Analog Models

The analog VCO models (`serdesphy_ana_cdr_vco.v` and `serdesphy_ana_pll_vco.v`)
contain timing constructs (`@(...)`) inside `` `ifndef SYNTHESIS `` guards.
During the GDS flow, `SYNTHESIS` is not defined, causing verilator to lint
these behavioral constructs as errors.

**Fix**: Added `LINTER_DEFINES: ["SYNTHESIS"]` to `user_config.json` to ensure
the timing-behavioral code is excluded during linting.

### Pyosys / Yosys Integration

LibreLane 3.0.0 calls `yosys -y` (pyosys mode) for synthesis. The system yosys
0.52 does not support this flag. A wrapper script at `/usr/bin/yosys` translates
the `-y` flag by running the pyosys Python script directly.

Additionally, the `abc -fast` option used in LibreLane's `synthesize.py` is not
supported by the pyosys module's ABC integration. This was patched by removing
`-fast` from the `abc` and `opt` calls in
`actions/gds/venv/lib/python3.11/site-packages/librelane/scripts/pyosys/synthesize.py`.

### OpenSTA / OpenROAD

OpenROAD provides both `openroad` and `sta` binaries. These must be in the system
PATH for the placement, routing, and timing analysis steps to succeed.

## Output

The GDS flow produces output in `runs/wokwi/` including:

- `*-yosys-synthesis/` — Gate-level netlist (`*.nl.v`)
- `*-openroad-*` — Placement, routing, and timing results
- `final/` — Final GDS, DEF, and LEF files
- `reports/` — DRC and LVS reports

## GitHub Actions

The `.github/workflows/gds.yaml` workflow runs this same flow in a Docker container
on GitHub's Ubuntu 24.04 runners, which have all tools pre-installed.