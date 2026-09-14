# PLL Implementation Plan

Covers `src/analog/ana_pll/` in full: `serdesphy_ana_pll.v` (top),
`serdesphy_ana_phase_frequency_detector.v`, `serdesphy_ana_pll_charge_pump.v`,
`serdesphy_ana_pll_loop_filter.v`, `serdesphy_ana_pll_vco.v`,
`serdesphy_ana_frequency_divider.v`. Also see `serdesphy_ana_loopback_switch.v`
(same directory, lower priority, listed at the end).

## 1. Spec requirements (`docs/info.md` §4.1, §5.5)

| Parameter | Value |
|---|---|
| Reference input | 23.5–24.5 MHz (nominal 24.0) |
| Output | 235–245 MHz (nominal 240), 10× multiplication |
| Lock time | 8–10 µs typ/max |
| Jitter (RMS) | 50–100 ps |
| VCO tuning range | 200–400 MHz |
| `VCO_TRIM[3:0]` | 0x0→~200 MHz, 0x8→~240 MHz (nominal), 0xF→~400 MHz |
| `CP_CURRENT[1:0]` | 0x0=10µA, 0x1=20µA, 0x2=40µA (default), 0x3=80µA |
| `PLL_RST` | active-high, default 1 (held in reset at power-up) |
| `PLL_BYPASS` | routes `clk_ref_24m` straight to `clk_240m_out` for test |

## 2. Current state (behavioral RTL)

All five sub-blocks exist as digital placeholders (see
`01-spec-vs-implementation.md` §3.6 for the detailed critique):

- **PFD** (`serdesphy_ana_phase_frequency_detector.v`): a real, if simplistic,
  bang-bang-style up/down pulse generator based on rising-edge ordering of
  `clk_ref` vs `clk_feedback`. Reasonable starting point for the digital
  *interface* but not representative of a true tri-state PFD's dead-zone
  behavior.
- **Charge pump** (`serdesphy_ana_pll_charge_pump.v`): output tied to
  `1'b0` — a pure placeholder, `cp_current` has no effect.
- **Loop filter** (`serdesphy_ana_pll_loop_filter.v`): a digital
  up/down integrator+averager. Since the charge pump never asserts
  `charge_in`, this always decays to `0` and stays there — dead in practice.
- **VCO** (`serdesphy_ana_pll_vco.v`): fixed ~240 MHz toggle in simulation,
  ignores `vco_control` entirely; synthesizes to constant 0 (`` `ifdef
  SYNTHESIS ``).
- **÷10 feedback divider** (`serdesphy_ana_frequency_divider.v`): a genuine
  counter-based ÷10 with 50% duty correction — this one is fine as a
  behavioral stand-in for the divider's *logical function*, though a real
  divider running off a ring VCO would typically be a true-single-phase-clock
  (TSPC) or CML divider for speed/power, not a synchronous counter.
- **Lock detection**: purely time-based (`serdesphy_ana_pll.v`'s
  `STATE_ACQUIRE` counts a fixed 240 cycles), independent of any actual
  frequency error.

**Net effect**: the loop is open. This is acceptable for digital-only
bring-up (downstream logic gets a stable clock and a lock pulse at roughly
the right latency) but proves nothing about the real analog design.

## 3. Proposed circuit topology (SKY130)

A charge-pump PLL with a current-starved ring VCO is the standard choice for
this frequency range and area budget in a Tiny Tapeout SKY130 shuttle slot:

- **VCO**: 3- or 5-stage current-starved differential (or single-ended, if
  area-constrained) ring oscillator using `sky130_fd_pr__nfet_01v8`/
  `pfet_01v8` devices, tail current set by `vco_control` through a
  current-mirror bias. Target Kvco ≈ (400−200 MHz)/(full control range) —
  size the mirror so `VCO_TRIM`'s 16 coarse steps + the fine charge-pump
  control together cover 200–400 MHz with the 240 MHz nominal point roughly
  centered in the fine-tune range at `VCO_TRIM=0x8`, per the spec's trim
  table.
- **PFD**: classic two-DFF + AND-reset tri-state PFD (the standard
  "Dead-zone-free" topology), producing true `UP`/`DN` pulses to the charge
  pump — a straightforward standard-cell-style digital block, easy first
  sub-circuit to lay out since it's mostly digital gates.
- **Charge pump**: single-ended (simpler, adequate for this frequency/jitter
  budget) current-steering charge pump with 4 selectable current levels
  (10/20/40/80 µA per `CP_CURRENT`) via binary-weighted current mirrors
  switched by `cp_current[1:0]`.
- **Loop filter**: passive 2nd-order RC (series R + C, plus a small shunt C
  to suppress reference spurs) sized for the target loop bandwidth. Rule of
  thumb: loop bandwidth ≈ f_ref/10 to f_ref/20 for a type-II charge-pump PLL
  targeting the 8–10 µs lock spec at 24 MHz reference — start around
  1–2 MHz loop bandwidth and iterate against the lock-time and jitter specs
  together (they trade off directly: wider bandwidth locks faster but tracks
  more reference/charge-pump noise).
- **÷10 feedback divider**: true single-phase clock (TSPC) or CML divider
  chain (e.g. ÷2 → ÷5, or a fully custom ÷10) if it needs to run reliably at
  the VCO's full 400 MHz worst-case output; a synchronous counter (as in the
  current behavioral model) is a fine functional reference but likely too
  slow/power-hungry as a real circuit at this node unless a standard-cell
  ÷10 comfortably meets timing at 400 MHz in the target corner — check this
  early, it determines whether the divider needs custom transistor-level
  design at all or can stay a synthesized digital block (in which case it
  doesn't need its own `schematic/`/`layout/` under the dual-flow framework
  — a good candidate to resolve to "digital" rather than "circuit" in
  `view.json`).
- **Lock detector**: real designs typically compare divided-feedback phase
  against reference over N cycles and assert lock only within a phase-error
  window (e.g. via a second, lower-gain phase comparator) — this replaces
  the fixed-cycle-count placeholder with something that actually reflects
  frequency/phase convergence, and can be built either as an analog
  peak-detector circuit or a fully digital phase-error counter fed from a
  higher-resolution digital PFD output. Digital is likely more practical
  here.

## 4. Design & verification procedure

1. **Schematic capture in xschem**: build the VCO, PFD, charge pump, and
   loop filter as separate xschem sheets under
   `src/analog/ana_pll/serdesphy_ana_pll_vco/schematic/` etc. (see
   `02-analog-digital-dual-flow-framework.md` for the directory convention),
   using `sky130_fd_pr` device symbols from the open_pdk xschem library.
2. **VCO characterization (ngspice)**:
   - DC sweep of `vco_control` → oscillation frequency; confirm 200–400 MHz
     range and roughly monotonic Kvco.
   - Corner sweep (tt/ff/ss × -40/27/85°C × 1.71–1.89V `DVDD`) — SKY130 ring
     oscillators shift substantially across process corners, so `VCO_TRIM`'s
     coarse range needs enough margin to re-center the tuning curve in the
     worst corner, not just typical.
   - Transient startup: confirm oscillation starts reliably from `rst_n`
     release across corners (ring oscillators can have startup/latch-up
     failure modes at extreme corners).
   - Phase noise / jitter: `.noise` analysis or transient jitter extraction
     (period-to-period jitter from a long transient run) to check against
     the 50–100 ps RMS spec.
3. **Loop-level closure (ngspice, full PLL testbench)**:
   - Transient lock-time measurement from `pll_rst` release to phase-error
     settling within spec, across corners — compare against the 8–10 µs
     target.
   - Loop-gain/phase-margin check (small-signal AC around the loop, or a
     Middlebrook-style injection) to confirm stability margin before
     committing to layout.
   - Bypass-mode functional check (`pll_bypass` routing `clk_ref` straight
     through) — this path is currently digital-only in `serdesphy_ana_pll.v`
     and can likely stay a digital mux even after the analog VCO/PFD/CP are
     real, since it only needs to select between two existing digital clock
     nets.
4. **Layout (magic)**:
   - VCO: matched stage layout (identical stage geometry, symmetric routing)
     is important for duty-cycle and jitter — common practice is a folded/
     ring layout with matched parasitic capacitance per stage.
   - Charge pump: matched up/down current mirror devices (common-centroid or
     interdigitated) to minimize static phase offset.
   - Keep the whole PLL analog island away from digital switching noise —
     use guard rings (`sky130_fd_pr` substrate/well taps) and, if the Tiny
     Tapeout shuttle's shared-die floorplan allows it, place it near the
     edge of this project's tile away from digital toggling activity.
5. **DRC/LVS/PEX** per the framework doc, then **re-run step 2/3's key
   testbenches against the extracted (PEX) netlist** — parasitics
   (especially loop-filter routing R/C and VCO stage capacitance) can shift
   center frequency and loop bandwidth meaningfully at this frequency, so
   this is not a formality.
6. **Cross-check against the behavioral model**: run `compare_views.py`
   (per `02-analog-digital-dual-flow-framework.md`) — center frequency,
   lock time, and (once the behavioral model gains a math upgrade per §5
   below) jitter should all land within agreed tolerance of the SPICE
   results before marking this cell `golden`.

## 5. Upgrade path for the behavioral model (do this in parallel, cheaply)

Independent of the circuit work, the current behavioral VCO/loop is a poor
stand-in for anything beyond "give downstream logic a clock." A cheap,
still-synthesizable-looking improvement that unblocks better full-chip
verification *before* the circuit exists:

- Give `serdesphy_ana_pll_vco.v` a real (if simplified) Kvco relationship:
  `period = nominal_period - Kvco_model * (vco_control - center)`, so
  `VCO_TRIM` and the loop filter's output visibly move the simulated
  frequency. Keep it `` `ifndef SYNTHESIS `` as today.
- Make `serdesphy_ana_pll_charge_pump.v` actually pump (drive `charge_out`
  as a real up/down current proxy, e.g. a signed `real` or small fixed-point
  value scaled by `cp_current`) instead of tying to `1'b0`, so the loop
  filter's integrator has something real to integrate.
- Change lock detection to key off actual frequency-error convergence
  (compare `feedback_clk` period against `clk_ref` period over a window)
  rather than a fixed counter, so `PLL_LOCK` timing responds to
  `VCO_TRIM`/`CP_CURRENT` the way real silicon will.

This closes a chunk of the §3.6 gap in `01-spec-vs-implementation.md` without
waiting on the circuit design, and gives the eventual `compare_views.py`
equivalence check something non-trivial to actually compare.

## 6. Milestones / sign-off checklist

- [ ] Behavioral model upgraded per §5 (unblocks better digital verification now)
- [ ] Schematic captured in xschem for VCO, PFD, charge pump, loop filter
- [ ] VCO tuning range/Kvco verified across corners in ngspice
- [ ] Full loop lock-time and phase-margin verified across corners in ngspice
- [ ] Layout complete in magic, DRC clean
- [ ] LVS clean (extracted vs. schematic)
- [ ] Post-PEX re-simulation confirms spec (lock time, tuning range) still met
- [ ] `compare_views.py` passes behavioral-vs-SPICE within tolerance
- [ ] `view.json` status → `golden`, `target_for_tapeout: "circuit"`
- [ ] Digital-side fixes from `01-spec-vs-implementation.md` §2.1/§2.3 landed (PLL_LOCK gating, register reset defaults) — these are independent of the circuit work and should not wait for it
