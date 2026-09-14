# CDR + CDR VCO Implementation Plan

Covers `src/analog/ana_rx/serdesphy_ana_cdr.v` and
`src/analog/ana_rx/serdesphy_ana_cdr_vco.v`. This is the most complex of the
four priority analog blocks — tackle it last, after the PLL VCO work
(`pll/README.md`) has proven out the dual-flow framework for a ring
oscillator, since the CDR VCO is architecturally very similar.

## 1. Spec requirements (`docs/info.md` §4.3, §5.6)

| Parameter | Value |
|---|---|
| Architecture | Bang-bang phase detector, Alexander (3x oversampling / early-late) |
| Acquisition range | ±2000 ppm |
| Lock time | 50–100 µs |
| Tracking bandwidth | ~1 MHz |
| Phase error (RMS) | 5–10 UI... wait, check spec: 5-10 (units listed as "UI" in §4.3 but this is almost certainly a documentation typo for a sub-UI fraction, e.g. milli-UI or a percentage — a phase error of 5-10 whole unit intervals would mean the CDR isn't tracking at all. **Flag this for the datasheet author to correct** (likely intended: 0.05-0.10 UI, consistent with the CDR_LOCK criterion below). |
| `CDR_GAIN[2:0]` | loop gain, recommended range 0x3-0x6, default 0x4 |
| `CDR_FAST_LOCK` | faster acquisition mode |
| `CDR_LOCK` criterion (§5.7) | phase error <0.1 UI for >64 consecutive bits |

## 2. Current state (behavioral RTL)

`serdesphy_ana_cdr.v` samples `serial_data` on two consecutive `clk_240m_rx`
edges (`serial_data_prev`/current) to form an early/late pair — a genuine, if
minimal, Alexander-style sampling structure. `cdr_gain` scales a fixed
±offset applied to a mid-scale `phase_detector` register
(`8'h80 ± cdr_gain`), and `cdr_fast_lock` doubles the correction applied to
`vco_control` during acquisition. Lock is declared by a fixed cycle counter
(600 cycles fast-lock / 1200 normal), **not** by measuring actual phase-error
convergence — so today's `CDR_LOCK` timing is unrelated to `CDR_GAIN` in any
physically meaningful way, and the §5.7 "<0.1 UI for 64 consecutive bits"
criterion isn't implemented at all.

`serdesphy_ana_cdr_vco.v` is architecturally identical to the PLL VCO
(`pll/README.md` §2): fixed ~240 MHz in simulation, ignores `cdr_control`,
constant-0 placeholder for synthesis.

**The most important current-state fact, already called out as Finding 2.2
in `01-spec-vs-implementation.md`:** the CDR VCO's output (`cdr_clk_240m`) is
used internally within `serdesphy_pma.v` to clock the RX receiver and the
phase detector, but the clock actually exported as `clk_240m_rx` to the rest
of the chip is hard-wired to the **TX PLL's** clock instead
(`serdesphy_pma.v:224`). This must be fixed before any of this block's real
circuit work is meaningful end-to-end — otherwise a real CDR VCO would be
built and characterized but its output would never actually reach the RX
digital logic.

## 3. Proposed circuit topology (SKY130)

- **CDR VCO**: same ring-oscillator approach as the PLL VCO
  (`pll/README.md` §3) — reuse that design's stage topology and layout
  pattern rather than developing a second, different VCO circuit from
  scratch. The two VCOs *can* share a design (same schematic, same layout
  cell, different instantiation/bias point) unless the CDR's tracking
  bandwidth requirement (~1 MHz, meaning it needs to respond faster
  per-update than the PLL, which only needs to settle once at power-up)
  pushes toward a different Kvco or a different number of stages — check
  this early rather than assuming reuse works, but default to reuse as the
  starting point.
- **Alexander (bang-bang) phase detector**: the classic 3-flip-flop
  structure — sample data at the recovered clock edge and at the mid-bit
  (90°-shifted) edge, XOR-compare consecutive data samples against the
  mid-bit sample to produce early/late decisions. This needs a
  quadrature (0°/90°) version of the recovered clock, which the current
  behavioral model doesn't have (it approximates "early/late" from two
  consecutive full-rate samples instead) — real quadrature generation
  typically comes from tapping two stages of the ring VCO directly (a
  natural byproduct of a ring topology, unlike an LC VCO), which is one
  more reason to keep the CDR VCO a ring design consistent with the PLL.
- **Digital loop filter / charge pump equivalent**: bang-bang PDs are
  inherently digital-output (early/late, not a continuous error signal), so
  the "charge pump" here is typically a simple up/down counter or
  digitally-implemented low-pass (matching `CDR_GAIN`'s step size) feeding
  either a digital-to-analog interface into an analog VCO control node, or a
  fully digital "control word" if going the digitally-controlled-oscillator
  (DCO) route instead of a classic analog-tuned VCO. **Recommendation**:
  given `CDR_GAIN`, `CDR_FAST_LOCK`, and `VCO_TRIM`-style controls are
  already digital register fields (§5.6), a mostly-digital loop (bang-bang
  PD → digital accumulator → small DAC or binary-weighted-capacitor-bank DCO
  control) is a lower-risk, more Tiny-Tapeout-appropriate architecture than a
  full analog charge-pump CDR, and it keeps consistent tooling (mostly
  digital design + a small DAC/varactor-bank analog tail) rather than a
  second fully analog charge-pump/loop-filter design in addition to the
  PLL's.
- **Lock detector**: needs the real §5.7 criterion — phase error magnitude
  below a threshold for 64 consecutive bit periods. Implementable digitally
  as a saturating up/down counter driven by the bang-bang PD's early/late
  decisions (increment on "in-window", reset or decrement on "out-of-window"
  early/late), asserting lock once the counter saturates — a natural
  extension of the existing digital PD structure, replacing the current
  fixed-cycle-count placeholder.

## 4. Design & verification procedure

1. **Fix the digital plumbing first** (see `01-spec-vs-implementation.md`
   §4.2): remove `assign clk_240m_cdr = pll_clk_240m;`, wire the real
   `cdr_clk_240m` through, and build (or reuse the orphaned
   `serdesphy_deserializer_if.v` as a starting point for) the CDC boundary
   between the recovered-clock domain and `clk_24m`. Do this before
   investing in the circuit-level work below — it's cheap, and it determines
   what the circuit actually needs to interface with (e.g. whether a
   quadrature output is exposed to the digital side at all, or stays
   internal to the analog CDR block).
2. **Reuse the PLL VCO's schematic/layout as the CDR VCO's starting point**
   (per §3) — capture in xschem under
   `src/analog/ana_rx/serdesphy_ana_cdr_vco/schematic/`, add quadrature taps
   if the Alexander PD design needs them.
3. **Phase detector + digital loop verification (ngspice + digital
   co-simulation)**:
   - This block is a genuinely mixed-signal loop (analog VCO + mostly
     digital PD/accumulator) — plan for a mixed-signal cosimulation setup
     (e.g. ngspice's XSPICE digital primitives, or a Verilog-AMS/co-sim
     bridge if the toolchain supports it) rather than trying to do the whole
     loop in pure SPICE or pure RTL. If that tooling isn't readily available,
     an acceptable fallback is characterizing the VCO and PD as separate
     SPICE blocks, and validating loop-level lock/tracking behavior in the
     upgraded behavioral model (§5 below) cross-checked against
     block-level SPICE specs, rather than a full transistor-level
     closed-loop transient.
   - Acquisition range: sweep an input data pattern with a synthetic
     frequency offset (±2000 ppm relative to the VCO's free-running
     frequency) and confirm the loop acquires lock within 50–100 µs.
   - Tracking bandwidth: inject a slow sinusoidal phase modulation on the
     input data and find the -3dB tracking bandwidth, target ~1 MHz.
   - Lock/unlock behavior against the corrected §5.7 criterion (0.1 UI /
     64 bits) — including confirming the datasheet's "5-10 UI" phase-error
     spec (see §1 above) gets corrected before it's used as a design target
     anywhere else.
4. **Layout (magic)**: VCO layout inherits from the PLL VCO's pattern
   (§3); phase detector is mostly digital standard-cell-style logic, low
   layout risk. Watch clock-tree matching between the quadrature taps if
   used — skew between the 0°/90° recovered clocks directly becomes phase
   detector offset.
5. **DRC/LVS/PEX**, then **re-run the acquisition-range and tracking-
   bandwidth testbenches against the PEX netlist**.
6. **Cross-check against the behavioral model** via `compare_views.py`,
   after the behavioral upgrade in §5.

## 5. Upgrade path for the behavioral model (do this in parallel, cheaply)

Same rationale as `pll/README.md` §5 — cheap RTL-only improvements that
unblock better full-chip verification before the circuit exists:

- Give `serdesphy_ana_cdr_vco.v` a real Kvco-style frequency response to
  `cdr_control` (can literally share the model added to the PLL VCO).
- Add a configurable frequency-offset injection point on the CDR's data
  input path (a testbench knob, not a chip-visible signal) so `±2000 ppm`
  acquisition can actually be exercised in simulation.
- Replace the fixed-cycle-count lock detector with the real §5.7 criterion
  (phase error window + 64-consecutive-bit saturating counter) — this is
  useful even before the circuit exists, since it makes `CDR_LOCK`'s
  simulated behavior actually depend on `CDR_GAIN`/`CDR_FAST_LOCK`, which it
  currently doesn't in any meaningful way.
- **Do this only after the clock-domain fix in §4 step 1** — there's limited
  value in making the lock-detection logic more realistic while the block
  it's supposed to be qualifying (the recovered clock) is still silently
  substituted with the TX PLL's clock.

## 6. Milestones / sign-off checklist

- [ ] Digital clock-domain fix landed (`clk_240m_cdr` no longer aliased to the PLL clock; real CDC boundary in place)
- [ ] Behavioral model upgraded per §5 (Kvco model, frequency-offset injection, real lock criterion)
- [ ] Datasheet phase-error spec typo (§4.3, "5-10 UI") corrected/clarified with the author
- [ ] CDR VCO schematic captured (reusing PLL VCO topology), quadrature taps added if needed
- [ ] Phase detector schematic/logic captured
- [ ] Acquisition range (±2000 ppm) verified across corners
- [ ] Tracking bandwidth (~1 MHz) verified across corners
- [ ] Lock detector verified against corrected §5.7 criterion
- [ ] Layout complete in magic, DRC clean
- [ ] LVS clean
- [ ] Post-PEX re-simulation confirms acquisition/tracking spec still met
- [ ] Co-design checkpoint with `rx_receiver/README.md` closed (input jitter/timing budget)
- [ ] `view.json` status → `golden`, `target_for_tapeout: "circuit"`
