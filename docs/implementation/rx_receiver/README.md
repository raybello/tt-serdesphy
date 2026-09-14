# RX Differential Receiver Implementation Plan

Covers `src/analog/ana_rx/serdesphy_ana_rx_differential_receiver.v`. (The
sibling file `serdesphy_ana_deserializer.v` in the same directory is
currently orphaned — see `01-spec-vs-implementation.md` §1 — out of scope
here unless a future decision reintroduces analog-domain deserialization.)

## 1. Spec requirements (`docs/info.md` §3.1, §4.3, §7.3)

| Parameter | Value |
|---|---|
| Interface | CML, 100 Ω differential |
| Sensitivity | ~10 mV_pp minimum differential |
| Function | limiting amplifier (large gain, output saturates to rail-to-rail digital swing regardless of input amplitude above sensitivity) |
| Data rate | 240 Mbps |
| Loopback | must accept the internal loopback tap in addition to the external `RXP`/`RXN` pads |
| Analog isolation | must produce a defined/safe output when `ISO_EN=1` |

## 2. Current state (behavioral RTL)

`serdesphy_ana_rx_differential_receiver.v` models the receiver as a clocked
digital comparator: `rxp_mux && !rxn_mux → 1`, `!rxp_mux && rxn_mux → 0`,
common-mode → hold previous value (a crude hysteresis proxy), muxing between
`lpbk_txp/txn` and the external pads based on `lpbk_en`. This correctly
captures the *functional* behavior (differential-to-single-ended,
hold-on-ambiguity) for driving downstream digital logic in simulation, but
has no sensitivity threshold, no bandwidth/gain modeling, and — being
clocked rather than combinational/continuous-time — implicitly assumes the
input is already synchronous to `clk`, which a real limiting amplifier's
output is not (it's the very thing the CDR has to lock onto). This is a
reasonable placeholder for exercising the digital datapath but not a stand-in
for the receiver's actual analog behavior.

## 3. Proposed circuit topology (SKY130)

- **Front end**: multi-stage differential limiting amplifier — 2-3 cascaded
  differential-pair gain stages (resistively or diode-connected-load loaded)
  with enough small-signal gain per stage that the ~10 mV_pp input
  sensitivity spec is met with margin after accounting for input-referred
  offset from device mismatch (this is usually the dominant sensitivity
  limiter in a design at this scale, not gain-bandwidth). A single stage
  is unlikely to have enough gain-bandwidth product to fully limit a 10 mV
  input to rail-to-rail digital swing at 240 Mbps within one bit period,
  hence the cascade.
- **Input stage headroom/biasing**: since `AVDD` is 3.3V and the front end
  needs to accept a differential signal from either the external RX pads or
  the internal loopback tap (from the TX driver, §3 of `tx_driver/README.md`),
  the input common-mode range must cover both the expected external-link
  common mode and the TX driver's own output common mode — this is a
  concrete co-design checkpoint between the two blocks.
- **Output stage**: a final CML-to-CMOS (or CML-to-rail) converter/buffer
  producing a clean digital `serial_data` logic level compatible with the
  downstream 240 MHz CDR sampling logic, i.e. this is where the
  "limiting" behavior actually resolves into a hard 0/1.
- **Isolation**: `iso_en=1` should force the output stage to a defined
  logic level (matching the digital behavioral model's `1'b0` choice is
  fine) rather than leaving the front end floating/oscillating on noise —
  typically done by clamping the output-stage differential pair rather than
  trying to fully power down the front end (faster to re-enable).
- **Signal detect**: the spec doesn't define a formal "signal detect"
  threshold circuit, but the behavioral model exposes `signal_detected` —
  worth deciding whether this becomes a real amplitude/activity detector
  (e.g. envelope detector comparing against a reference) or stays a purely
  digital "did we see recent transitions" heuristic computed downstream in
  the CDR/deserializer logic instead of in the analog front end. Given the
  CDR already does transition-based sampling (`serdesphy_ana_cdr.v`), the
  simpler and lower-risk choice is to **not** build a dedicated analog
  signal-detect circuit and instead keep deriving activity/signal-detect
  digitally from CDR transition statistics, same as today's behavioral
  model's `signal_detected_reg` logic — flag this as a design decision to
  confirm rather than an open circuit-design task.

## 4. Design & verification procedure

1. **Schematic capture in xschem**: cascaded differential gain stages +
   output buffer, under
   `src/analog/ana_rx/serdesphy_ana_rx_differential_receiver/schematic/`.
2. **Sensitivity/gain verification (ngspice)**:
   - Small-signal AC gain per stage and cascaded, across corners — confirm
     enough gain-bandwidth to resolve a 10 mV_pp differential input to a
     valid digital output within a bit period at 240 Mbps, worst corner
     included.
   - Input-referred offset (Monte Carlo mismatch simulation, `sky130_fd_pr`
     mismatch models) — this determines the *real* sensitivity floor; if
     offset approaches or exceeds 10 mV, either add input offset
     cancellation (harder, adds circuit complexity) or revisit whether the
     spec's 10 mV figure needs a note about required input signal margin
     above device mismatch.
3. **Transient/BER-proxy verification (ngspice)**:
   - Apply a 240 Mbps PRBS-7 differential input at swing levels spanning the
     full 400–800 mVpp TX range (co-simulated with, or a SPICE model
     matching, `tx_driver/README.md`'s driver) attenuated down toward the
     10 mV sensitivity floor (representing channel loss) — confirm correct
     digital recovery at both extremes.
   - Common-mode rejection check — inject common-mode noise/offset and
     confirm it doesn't corrupt the differential decision.
   - Isolation-mode and loopback-mux functional check (mirrors the digital
     behavioral model's existing test intent).
4. **Layout (magic)**:
   - Matched differential-pair layout per stage (as with the TX driver, and
     for the same offset-minimization reason — offset here directly sets
     sensitivity, so this matters more here than almost anywhere else in the
     analog design).
   - Keep RX input routing (`RXP`/`RXN` from `IO4`/`IO5`, §3.1) as short and
     symmetric as possible — parasitic capacitance/mismatch on this specific
     net pair directly trades against sensitivity margin.
5. **DRC/LVS/PEX**, then **re-run the sensitivity and transient testbenches
   against the PEX netlist** — input-path parasitics are the most sensitive
   part of this block to layout parasitics.
6. **Cross-check against the behavioral model** via `compare_views.py` —
   logical-only comparison initially (differential polarity → digital
   output, hold-on-common-mode behavior), same caveat as the TX driver plan.

## 5. Co-design checkpoints

- **With `tx_driver/README.md`**: TX output common-mode/swing must fall
  within this receiver's valid input range, for both the external-link case
  and the internal loopback case (which may have different effective
  attenuation/loading than the external 100 Ω link).
- **With `cdr_vco/README.md`**: this receiver's output timing/jitter
  directly feeds the CDR's bang-bang phase detector — any additional delay
  or jitter contributed by the limiting amplifier's own bandwidth should be
  budgeted into the CDR's phase-error tolerance, not discovered late.

## 6. Milestones / sign-off checklist

- [ ] Schematic captured in xschem (cascaded gain stages + output buffer)
- [ ] Gain/bandwidth verified sufficient for 10 mV_pp @ 240 Mbps across corners
- [ ] Input-referred offset characterized via Monte Carlo, sensitivity floor confirmed compatible with 10 mV spec
- [ ] Transient PRBS recovery verified across the full 400-800 mVpp (attenuated to ~10 mV) input range
- [ ] Isolation mode and loopback mux verified functionally correct
- [ ] Layout complete in magic, DRC clean, matched differential pairs
- [ ] LVS clean
- [ ] Post-PEX re-simulation confirms sensitivity/timing spec still met
- [ ] Co-design checkpoints with TX driver and CDR closed
- [ ] `view.json` status → `golden`, `target_for_tapeout: "circuit"`
