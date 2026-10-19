# TX Differential Driver Implementation Plan

Covers `src/analog/ana_tx/serdesphy_ana_tx_differential_driver.v`. (The
sibling file `serdesphy_ana_serializer.v` in the same directory is currently
orphaned — see `01-spec-vs-implementation.md` §1 — and is out of scope here
unless a future decision reintroduces analog-domain serialization.)

## 1. Spec requirements (`docs/info.md` §3.1, §4.2, §7.3)

| Parameter | Value |
|---|---|
| Interface | CML, 100 Ω differential impedance |
| Output swing | 400–800 mVpp (typ 600) |
| Supply | AVDD 3.0–3.6V (typ 3.3) |
| Data rate | 240 Mbps (bit period 4.17 ns) |
| Analog isolation | must go high-Z / safe state when `ISO_EN=1` |
| Loopback | must continue driving normally so `serdesphy_ana_loopback_switch` can tap it internally |

## 2. Current state (behavioral RTL)

`serdesphy_ana_tx_differential_driver.v` is a registered digital
complementary pair: `txp <= serial_data; txn <= ~serial_data;` on
`clk` (240 MHz), with isolation/disable forcing both outputs low (not
actually high-Z, just `0`/`0` — fine for a digital sim proxy, not
representative of a real high-Z/common-mode-safe state). No swing, no
impedance, no rise/fall time modeling — a correct *logical* stand-in, no
electrical fidelity, which is appropriate for this stage.

## 3. Proposed circuit topology (SKY130)

This is the simplest of the four priority analog blocks — a good first
target to prove the full dual-flow pipeline end-to-end (schematic → SPICE →
layout → GDS → LVS-clean) before tackling the PLL/CDR.

- **Core**: current-mode logic (CML) driver — a differential pair
  (`sky130_fd_pr__nfet_01v8`, or a stacked cascode if headroom at 3.3V AVDD
  requires it) with a tail current source, driving into two 50 Ω on-chip (or
  I/O-pad) termination resistors to a common AVDD-referenced rail, giving a
  100 Ω differential load. Alternative if area/tail-current-source
  complexity is a concern for the shuttle: a simple resistively-loaded
  differential pair (poly or `sky130_fd_pr` diffusion resistors) is a
  reasonable lower-risk first pass, trading some supply-noise rejection for
  simplicity.
- **Swing control**: tail current (or, for the simpler resistor-loaded
  variant, load resistor value / a coarse-selectable ladder) sets
  `Vswing = I_tail * R_load`. To hit the 400–800 mVpp range with margin,
  size for the nominal 600 mVpp at typical corner with the tail current (or
  an equivalent digital trim, if a configurable output swing register bit
  is ever added — not currently in the spec's register map, so a fixed
  nominal design point sized for 600 mVpp is the simplest compliant choice
  unless the spec is extended).
- **Pre-driver**: a small CMOS buffer chain level-shifting the digital
  `serial_data` (1.8V-domain logic, arriving from the DVDD-domain digital
  core) up to properly switch the CML pair's gates without excessive
  rise/fall time at 240 Mbps — needs a clean 1.8V→3.3V-domain crossing at
  the pad boundary, consistent with how the project already splits DVDD
  (1.8V digital) from AVDD (3.3V analog I/O) per §7.2.
- **Isolation switch**: `iso_en` should put the driver in a genuine
  high-impedance/safe state (tail current off, outputs pulled to a defined
  common-mode rail) rather than actively driving `0`/`0` — driving a
  differential `0` still sources/sinks current through the 100 Ω
  termination and isn't a true isolated state.
- **Loopback tap**: the existing `serdesphy_ana_loopback_switch.v` taps
  `txp`/`txn` directly; in the real circuit this can remain a straightforward
  analog mux/pass-gate (e.g. `sky130_fd_pr` transmission gates) selecting
  between the TX driver's own output and the external `rxp`/`rxn` pads,
  feeding the RX differential receiver — this block is simple enough to
  likely resolve to "digital-adjacent" (a switch, not an active circuit) in
  the dual-flow framework, but still needs a real layout since it sits in
  the high-speed signal path and any added parasitic capacitance/loading
  affects both TX swing and RX sensitivity.

## 4. Design & verification procedure

1. **Schematic capture in xschem**: differential pair + tail source (or
   resistor-loaded variant) + pre-driver, under
   `src/analog/ana_tx/serdesphy_ana_tx_differential_driver/schematic/`.
2. **DC/swing verification (ngspice)**:
   - DC operating point across corners (tt/ff/ss × -40/27/85°C × AVDD
     3.0–3.6V) — confirm output swing stays within 400–800 mVpp everywhere,
     not just typical corner.
   - Common-mode level check — confirm the driver's common-mode output
     voltage is compatible with the RX receiver's expected input common-mode
     range (co-design point with `rx_receiver/README.md`).
3. **Transient/eye verification (ngspice)**:
   - 240 Mbps PRBS-7 pattern transient (reuse the digital PRBS generator's
     sequence as the stimulus, or a SPICE-native PRBS source) into a 100 Ω
     differential load with parasitic package/bond-wire model if available —
     measure rise/fall time, and eye height/width at the receiver end via a
     `.measure` sweep or post-processing the transient waveform.
   - Confirm rise/fall times are comfortably faster than the 4.17 ns bit
     period (a common target is ≤20% of UI, i.e. <0.83 ns 20-80% rise time)
     — this is the main risk area for a resistor-loaded/simple CML design at
     this node; if rise/fall time is marginal, revisit tail current sizing
     or pre-driver strength before committing to layout.
   - Isolation-mode check: confirm `iso_en=1` produces the intended safe
     state (whatever that's defined as — high-Z or a defined common-mode
     level) with no oscillation or floating-node risk.
4. **Layout (magic)**:
   - Symmetric, matched layout for the differential pair (common-centroid or
     tightly interdigitated) to minimize static offset/duty-cycle
     distortion.
   - Careful attention to the TX pad routing — this is a high-speed
     (240 Mbps) I/O path, so minimize parasitic capacitance on `txp`/`txn`
     routing between the driver and the `IO2`/`IO3` pads (per §3.1 pin
     table), and keep routing length-matched between `txp` and `txn` to
     avoid skew.
5. **DRC/LVS/PEX**, then **re-run the transient/eye testbench against the
   PEX netlist** — pad/routing parasitics are exactly what can eat into the
   rise-time margin checked in step 3, so this re-check matters more here
   than for a purely internal circuit.
6. **Cross-check against the behavioral model** via `compare_views.py` —
   since the behavioral model has no swing/timing fidelity today, the
   comparison at this stage is necessarily logical-only (does a `1`/`0` on
   `serial_data` produce the correct differential polarity, does `iso_en`
   correctly suppress output) until a companion IBIS-style or `real`-valued
   behavioral upgrade is added (optional — lower priority than the PLL/CDR
   behavioral upgrades in their respective plans, since the digital *logic*
   of this block is already correct).

## 5. Milestones / sign-off checklist

- [ ] Schematic captured in xschem (differential pair/CML core + pre-driver)
- [ ] DC swing verified 400–800 mVpp across corners in ngspice
- [ ] Transient eye/rise-time verified against 4.17 ns UI in ngspice
- [ ] Isolation mode verified safe (no floating nodes, defined state)
- [ ] Layout complete in magic, DRC clean, matched/symmetric pair
- [ ] LVS clean
- [ ] Post-PEX re-simulation confirms swing/timing spec still met with pad/routing parasitics
- [ ] Co-design checkpoint with `rx_receiver/README.md`: confirm TX common-mode/swing is compatible with RX input range, including the loopback path
- [ ] `view.json` status → `golden`, `target_for_tapeout: "circuit"`
