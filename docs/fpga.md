# FPGA Build for tt-serdesphy

This guide explains how to generate an FPGA bitstream for the
`tt-serdesphy` project, targeting the **IceStorm ICE40UP5K-B-EVN**
breakout board. This is the local equivalent of the
[`.github/workflows/fpga.yaml`](../.github/workflows/fpga.yaml) GitHub Actions job.

## Overview

The FPGA flow wraps the SerDes PHY top module (`tt_um_raybello_serdesphy_top`)
inside Tiny Tapeout's `tt_fpga_top` wrapper, which exposes the standard
Tiny Tapeout I/Os (`ui_in`, `uo_out`, `uio_in/out/oe`, `clk`, `rst_n`, `ena`)
mapped to FPGA GPIO pins via the board's constraints file.

The flow consists of three tools from the [oss-cad-suite](https://github.com/YosysHQ/oss-cad-suite):

| Step | Tool | Description |
|---|---|---|
| 1 | `yosys` | Synthesizes the Verilog RTL into an iCE40 gate-level netlist (JSON) |
| 2 | `nextpnr-ice40` | Places & routes the netlist onto the ICE40UP5K fabric |
| 3 | `icepack` | Converts the ASCII placement file (`.asc`) into a binary bitstream (`.bin`) |

## Prerequisites

### System tools (apt)

```bash
sudo apt-get update
sudo apt-get install -y iverilog yosys nextpnr-ice40 fpga-icestorm cmake
```

> **Note:** The Tiny Tapeout toolchain uses `yowasp-yosys` (a WASM build of
> yosys). If that is not available, you can shim it to use the system
> `yosys`:
> ```bash
> sudo ln -sf "$(which yosys)" /usr/local/bin/yowasp-yosys
> ```

### Python environment

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r actions/fpga/tt/requirements.txt        # tt-support-tools deps
pip install -r test/requirements.txt                  # cocotb, pytest
```

## Build Steps

### 1. Generate user configuration

The `tt_tool.py` script reads `info.yaml` and generates
`src/user_config.json`, which lists the design name, source files, and
target technology.

```bash
python actions/fpga/tt/tt_tool.py --create-user-config
```

This produces `src/user_config.json` (gitignored).

### 2. Create the FPGA wrapper top module

The `tt_fpga.py` `harden` command automatically generates a wrapper
module `src/_tt_fpga_top.v` from the template
`actions/fpga/tt/fpga/tt_fpga_top.v`, replacing `__tt_um_placeholder`
with the project's top module name (`tt_um_raybello_serdesphy_top`).
This wrapper instantiates the user design and connects it to the
Tiny Tapeout pinout.

### 3. Run the build

```bash
python actions/fpga/tt/tt_fpga.py --project-dir . harden
```

This performs all three synthesis/P&R/bitstream steps and outputs:

```
build/
├── 01-synth.log                              # yosys synthesis log
├── 02-nextpnr.log                            # nextpnr place & route log
├── tt_um_raybello_serdesphy_top.json         # post-synth netlist
├── tt_um_raybello_serdesphy_top.asc          # ASCII bitstream (post-P&R)
└── tt_um_raybello_serdesphy_top.bin          # Binary bitstream (ready to flash)
```

## Results

### Device utilization (ICE40UP5K)

```
ICESTORM_LC:   682/ 5280   (12%)
SB_IO:          26/   96   (27%)
SB_GB:           8/    8   (100%)
ICESTORM_RAM:    0/   30   (0%)
ICESTORM_PLL:    0/    1   (0%)
ICESTORM_DSP:    0/    8   (0%)
```

### Logic gate count

**682 LUT4 logic cells** (synthesized from the RTL):

| Component | Count |
|---|---|
| Standalone LUT4s (combinational only) | 444 |
| LUT4 + flip-flop pairs | 156 |
| Standalone flip-flops | 217 |
| Carry chains | 10 |
| Merged carry + LUT | 1 |

### Timing

```
Max frequency (clk_240m_cdr domain):  72.68 MHz  (target: 12 MHz — PASS)
Max frequency (clk_ref domain):      46.65 MHz  (PASS)
```

### Pin assignments

The FPGA pins are constrained by
`actions/fpga/tt/fpga/tt_fpga_fabricfoxv2.pcf`:

| FPGA Pin | Function |
|---|---|
| `X19/Y0/io1` | `clk` |
| `X13/Y31/io0` | `rst_n` |
| `X19/Y0/io0`–`X18/Y0/io1` | `ui_in[0:7]` |
| `X8/Y0/io0`–`X18/Y0/io0` | `uio[0:7]` (bidirectional) |
| `X8/Y31/io1`–`X7/Y0/io0` | `uo_out[0:7]` |

## Waveform

A Verilog timescale FST dump is generated during simulation. View with:

```bash
surfer test/tb.fst
# or
gtkwave test/tb.fst test/tb.gtkw
```

## Notes

- The analog sub-blocks (PLL VCO, CDR VCO, differential drivers/receivers)
  are implemented as behavioral Verilog models. They synthesize correctly
  but do not model true analog behavior on the FPGA.
- In `test_mode`, the serializer and deserializer are bypassed
  (`serializer_bypass` / `deserializer_bypass` tied to `test_mode`),
  allowing the digital datapath to be verified without analog behavior.
- The build directory (`actions/fpga/build/`) and the `tt` submodule
  (`actions/fpga/tt/`) are listed in `.gitignore`.
