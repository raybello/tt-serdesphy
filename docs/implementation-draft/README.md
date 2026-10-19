# Implementation Documentation

This directory tracks the gap between `docs/info.md` (the SKY130 SerDes PHY
datasheet/spec) and the RTL currently checked in under `src/`. It also lays
out the framework for taking the analog blocks under `src/analog/` from
behavioral Verilog stand-ins to real SKY130 circuits (schematic → SPICE →
layout → GDS) without breaking the digital simulation/synthesis flow.

## Contents

| Doc | Purpose |
|---|---|
| [`01-spec-vs-implementation.md`](01-spec-vs-implementation.md) | Full audit: what's implemented, what's wired, what's stubbed, what's outright disconnected, and concrete bugs found while cross-checking `docs/info.md` against `src/`. Start here. |
| [`00-fixes-applied.md`](00-fixes-applied.md) | Everything actually fixed since the audit above, file by file, verified against the live `uvm_tb` simulator - including several additional real, pre-existing bugs only discoverable by wiring the fixes together and running end-to-end traffic. Also documents what's now solidly verified vs. what remains genuinely open. **Read this one second**, right after the audit. |
| [`02-analog-digital-dual-flow-framework.md`](02-analog-digital-dual-flow-framework.md) | Directory layout, tooling (xschem/ngspice for schematic+SPICE, magic/klayout for layout+DRC/LVS), and build-system framework for maintaining a behavioral RTL view and a real circuit/GDS view of every analog block side by side. |
| [`pll/README.md`](pll/README.md) | Detailed implementation plan for the TX PLL (ring-VCO based, 24→240 MHz). |
| [`tx_driver/README.md`](tx_driver/README.md) | Detailed implementation plan for the CML TX differential driver. |
| [`rx_receiver/README.md`](rx_receiver/README.md) | Detailed implementation plan for the RX differential receiver / limiting amplifier. |
| [`cdr_vco/README.md`](cdr_vco/README.md) | Detailed implementation plan for the CDR (Alexander bang-bang PD) and its VCO. |

## TL;DR of the audit

The digital control plane (I2C/CSR, TX/RX packet-level datapath, POR) is in
good shape and mostly matches the spec. The weak points are:

1. **~25% of the checked-in RTL is orphaned** — written but never
   instantiated (`serdesphy_pll_ctrl`, `serdesphy_clock_manager`,
   `serdesphy_debug_mux`, `serdesphy_serializer_if`,
   `serdesphy_deserializer_if`, and the analog `serializer`/`deserializer`/
   `bias_generator`/`analog_debug_buffer`/`clk_enable` models).
2. **The CDR clock domain is not actually plumbed through** — `clk_240m_cdr`
   is hard-wired to the PLL clock (`serdesphy_pma.v:224`), so the RX digital
   logic never runs on a truly recovered/independent clock. This is fine as a
   loopback-testing shortcut but needs to be fixed before real CDR closure.
3. **`PLL_LOCK` (STATUS[0]) is accidentally gated by `TX_EN`**
   (`serdesphy_pcs.v:194`, via `serializer_ready`), which breaks the
   documented init sequence in §8.1 of the datasheet (it polls `PLL_LOCK`
   *before* enabling TX).
4. All the analog blocks are purely digital behavioral placeholders — none
   of them have a SPICE schematic, layout, or extracted netlist yet. That's
   expected at this stage but is the bulk of remaining work before tapeout.

See the audit doc for the full list with file/line references.
