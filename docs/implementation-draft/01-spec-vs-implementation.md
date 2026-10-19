# SPEC vs Implementation Audit

Source of truth: `docs/info.md` (datasheet v0.0.1). RTL reviewed: everything
under `src/` (45 Verilog files, digital + analog-behavioral).

> **Status update:** every finding in §2 below (2.1 through 2.5) has since
> been fixed and verified against the live `uvm_tb` simulator (Verilator).
> See [`00-fixes-applied.md`](00-fixes-applied.md) for exactly what changed,
> file by file, plus several additional real bugs that were only
> discoverable by actually wiring the fixes together and running end-to-end
> traffic through them - the findings below are left as originally written
> (describing the state *before* the fix) since they're still the clearest
> explanation of *why* each fix was needed; treat any present-tense RTL
> description in this file as describing the pre-fix behavior unless
> `00-fixes-applied.md` says otherwise.

## 1. Top-level hierarchy (what's actually wired today)

```
tt_um_raybello_serdesphy_top (src/project.v)      -- TinyTapeout pin mapping
 └─ serdesphy_top (src/serdesphy_top.v)
     ├─ serdesphy_pcs (src/digital/serdesphy_pcs.v)         "Physical Coding Sublayer"
     │   ├─ serdesphy_por                  (POR / power sequencing)
     │   ├─ serdesphy_reset_synchronizer   (CDC reset sync)
     │   ├─ serdesphy_csr_top              (I2C + register bank)
     │   │   ├─ serdesphy_i2c_slave
     │   │   │   ├─ serdesphy_registerInterface
     │   │   │   └─ serdesphy_serialInterface
     │   ├─ serdesphy_tx_top               (word_assembler → tx_fifo → tx_data_mux → manchester_encoder → serial shifter)
     │   │   ├─ serdesphy_word_assembler
     │   │   ├─ serdesphy_tx_fifo
     │   │   ├─ serdesphy_prbs_generator
     │   │   ├─ serdesphy_tx_data_mux
     │   │   └─ serdesphy_manchester_encoder
     │   └─ serdesphy_rx_top               (serial accumulator → manchester_decoder → rx_fifo → word_disassembler, + prbs_checker + alignment FSM)
     │       ├─ serdesphy_manchester_decoder
     │       ├─ serdesphy_rx_fifo
     │       ├─ serdesphy_word_disassembler
     │       └─ serdesphy_prbs_checker
     └─ serdesphy_pma (src/analog/serdesphy_pma.v)          "Physical Medium Attachment"
         ├─ serdesphy_ana_pll
         │   ├─ serdesphy_ana_phase_frequency_detector
         │   ├─ serdesphy_ana_pll_charge_pump
         │   ├─ serdesphy_ana_pll_loop_filter
         │   ├─ serdesphy_ana_pll_vco
         │   └─ serdesphy_ana_frequency_divider
         ├─ serdesphy_ana_tx_differential_driver
         ├─ serdesphy_ana_loopback_switch
         ├─ serdesphy_ana_rx_differential_receiver
         ├─ serdesphy_ana_cdr
         └─ serdesphy_ana_cdr_vco
```

### Orphaned RTL (written, never instantiated by anything — checked against
`src/`, `test/`, and `uvm_tb/`)

| File | What it does | Why it's dead |
|---|---|---|
| `src/digital/pll/serdesphy_pll_ctrl.v` | Enhanced PLL enable/lock FSM with proper hysteresis (`LOCK_COUNT_MAX`/`UNLOCK_COUNT`), status register, isolation sequencing | Commented out in `serdesphy_pcs.v:234-261`. `pcs.v` instead derives `pll_lock`/`pll_ready`/`pll_status`/`pll_error` directly from PMA's raw `serializer_ready`/`serializer_status` (see §3.1). |
| `src/digital/pll/serdesphy_clock_manager.v` | Base lock-counter clock-enable generator, instantiated *inside* `pll_ctrl` | Dead because `pll_ctrl` itself is dead. |
| `src/digital/common/serdesphy_debug_mux.v` | Proper 3-way debug mux (`vco_control`/`phase_detector`/`fifo_status` → `debug_analog[7:0]`) per §5.8 | Never instantiated. `dbg_ana` is instead driven directly by `reg_debug_enable[3]` in `serdesphy_csr_top.v:163` — a raw config bit, not a routed analog debug signal. |
| `src/analog/ana_common/serdesphy_ana_analog_debug_buffer.v` | Digital-to-analog buffer for the debug mux output | Dead (nothing feeds it; `dbg_ana` bypasses it entirely). |
| `src/digital/tx/serdesphy_serializer_if.v` | CDC + enable/reset sequencing FSM between `tx_top` and the analog serializer, including its own `serializer_clock` divider | Commented out in `serdesphy_pcs.v:337-357`. `serdesphy_top.v` connects `tx_serial_data` straight from `tx_top` to the PMA's TX driver instead. |
| `src/digital/rx/serdesphy_deserializer_if.v` | Symmetric CDC/sequencing FSM for the RX side, including a transition-counting "signal acquired" heuristic | Commented out in `serdesphy_pcs.v:386-407`. `rx_serial_data` comes straight from `deserializer_data` in the PMA. |
| `src/analog/ana_tx/serdesphy_ana_serializer.v` | 16:1 parallel-to-serial shift register with `load_data`/`data_ready` handshake | Never instantiated in `serdesphy_pma.v`. TX path instead passes `tx_top`'s already-bit-serial output straight to the differential driver (serialization happens digitally in `tx_top`'s 240 MHz shifter, not here). |
| `src/analog/ana_rx/serdesphy_ana_deserializer.v` | 1:16 serial-to-parallel shift register | Never instantiated. RX path instead accumulates bits inside `rx_top` itself. |
| `src/analog/ana_common/serdesphy_ana_bias_generator.v` | Sequenced TX/RX/VCO bias startup | Never instantiated anywhere in the PMA. |
| `src/analog/ana_common/serdesphy_ana_clk_enable.v` | Free-running ÷251 clock-enable pulse generator | Never instantiated; no clear owner even in the commented-out interfaces. |

**Why this matters:** none of this is broken exactly, but it means whoever
picks up this repo next will spend real time discovering that ~10 files (a
quarter of the RTL) are vestigial before they can trust the module graph.
Recommendation: either (a) delete the orphaned files and fold any logic worth
keeping (e.g. `pll_ctrl`'s lock hysteresis) into the live modules, or (b) if
they represent the intended *next* architecture (e.g. re-introducing the
`*_if` CDC layers once the CDR domain is real — see Finding 2 below), track
that explicitly in this doc's "left to connect" section instead of leaving
them silently unreferenced. Given the analysis in §2 and §3, **option (a) for
`pll_ctrl`/`clock_manager`/`debug_mux`/`analog_debug_buffer`, option (b) for
the `*_if` CDC modules** (they'll be needed once the CDR clock domain is
real) is the pragmatic split.

## 2. Critical / functional bugs found

These are conformance breaks against `docs/info.md`, not style issues.

### 2.1 `PLL_LOCK` is gated by `TX_EN` — breaks the documented init sequence

`docs/info.md` §8.1 step 5 says *"Poll STATUS[0] until PLL_LOCK asserts"*,
and this happens **before** step 6 *"Write 0x05 to TX_CONFIG (enable TX)"*.

But the actual signal chain is:

- `serdesphy_pcs.v:194`: `assign pll_lock = serializer_ready;`
- `serdesphy_pma.v:155`: `assign serializer_ready = serializer_enable && analog_en && pll_lock_raw;`
- `serdesphy_top.v:174`: `assign serializer_enable = tx_en && !iso_en;`

So `STATUS[0]` (`PLL_LOCK`) is mathematically ANDed with `tx_en`. Following
the datasheet's own init sequence, `tx_en` is still 0 when the host polls
`PLL_LOCK` — **the bit will never assert**, and the host will hang forever
per the documented procedure.

*Fix:* `pll_lock` must be a function of the PLL only (`pll_lock_raw` qualified
by `analog_en`/isolation), never of `serializer_enable`/`tx_en`. This is
exactly what the orphaned `serdesphy_pll_ctrl.v` does correctly — re-wiring
it (or porting its lock-qualification logic into `pcs.v`) fixes this.

### 2.2 The CDR clock domain is not actually independent of the TX PLL

`serdesphy_pma.v:220-224`:

```verilog
// Behavioral model: use the PLL clock for the CDR output so the RX shift
// register is phase-aligned with the TX serializer.  In silicon the CDR
// would achieve the same alignment by locking to the incoming data
// transitions.
assign clk_240m_cdr = pll_clk_240m;
```

The CDR VCO (`serdesphy_ana_cdr_vco`) *is* instantiated and its output
(`cdr_clk_240m`) *is* used to clock the RX differential receiver and the
bang-bang phase detector internally — but the clock that actually leaves the
PMA as `clk_240m_rx` (and clocks all of `serdesphy_rx_top`, i.e. the real
receive datapath) is silently substituted with the **TX PLL's** clock. In
other words, "CDR lock" today only reflects whether the internal
phase-detector counters have run long enough, not whether the RX digital
logic is genuinely running on a recovered clock derived from `rxp`/`rxn`.

This is a reasonable and clearly-commented shortcut for early digital
loopback bring-up (§4.3/8.1 loopback path: TX and RX share one clock so data
integrity tests aren't polluted by frequency offset), but it means:

- Frequency-offset acquisition (`±2000 ppm` per §4.3) can never be exercised
  in simulation as written.
- CDR tracking bandwidth (`~1 MHz` per §4.3) is unmeasurable — there's no
  independent clock to track.
- Once the analog CDR VCO becomes a real circuit (see
  `cdr_vco/README.md`), this `assign` **must** be removed and replaced with
  the actual `cdr_clk_240m` net, and the RX digital logic downstream needs a
  real CDC boundary (this is exactly the gap the orphaned
  `serdesphy_deserializer_if.v` was written to fill — see §1).

*Recommendation:* Track this explicitly as a TODO gate before any
loopback-passing testbench is treated as evidence the CDR works. Add a build
option (e.g. `ASSUME_TX_RX_COHERENT_CLOCK`) so both modes are simulatable and
this stops being silent.

### 2.3 CSR register reset defaults don't match §5 of the datasheet

`serdesphy_registerInterface.v:82-89` resets:

| Register | Spec default (§5) | RTL default | Match? |
|---|---|---|---|
| `PHY_ENABLE` (0x00) | `PHY_EN=0`, `ISO_EN=1` → `0x02` | `8'h02` | ✅ |
| `TX_CONFIG` (0x01) | all 0 | `8'h00` | ✅ |
| `RX_CONFIG` (0x02) | all 0 | `8'h00` | ✅ |
| `DATA_SELECT` (0x03) | all 0 | `8'h00` | ✅ |
| `PLL_CONFIG` (0x04) | `VCO_TRIM=0x8`, `CP_CURRENT=0x2`, `PLL_RST=1` → `0x68` | `8'h00` | ❌ |
| `CDR_CONFIG` (0x05) | `CDR_GAIN=0x4`, `CDR_RST=1` → `0x14` | `8'h00` | ❌ |
| `DEBUG_ENABLE` (0x07) | all 0 | `8'h00` | ✅ |

Practical effect: on reset, per spec the PLL and CDR should power up **held
in reset** (`PLL_RST=1`, `CDR_RST=1`) with the documented nominal trims
already latched, requiring firmware to explicitly release them (as the §8.1
init sequence does in steps 4 and 8). The current RTL instead starts the PLL
and CDR running immediately with `VCO_TRIM=0x0` (`~200 MHz`, not the nominal
`240 MHz`) and `CDR_GAIN=0x0` (below the recommended `0x3–0x6` range). This
doesn't crash anything (the PLL will still lock at whatever frequency the
trim gives it), but it silently diverges from the documented default
operating point and from what §8.1 assumes firmware will observe.

*Fix:* change the reset values in `serdesphy_registerInterface.v` to `8'h68`
and `8'h14` respectively.

### 2.4 Reserved register bits are not masked to 0 (except `PHY_ENABLE`)

Spec §5 marks unused bits "Reserved / — / 0" for every register, and
`TEST_CHECKLIST.md` REG_004 checks this only for `PHY_ENABLE`. Looking at
`serdesphy_registerInterface.v:98-107`, only the `PHY_ENABLE` write path
masks reserved bits:

```verilog
3'h0: reg_phy_enable   <= {{6{1'b0}}, dataIn[1:0]};   // masked
3'h1: reg_tx_config    <= dataIn;                     // NOT masked
3'h2: reg_rx_config    <= dataIn;                     // NOT masked
3'h3: reg_data_select  <= dataIn;                     // NOT masked
3'h4: reg_pll_config   <= dataIn;                     // NOT masked
3'h5: reg_cdr_config   <= dataIn;                     // NOT masked
3'h7: reg_debug_enable <= dataIn;                     // NOT masked
```

`TX_CONFIG[7:4]`, `RX_CONFIG[7:4]`, `DATA_SELECT[7:2]`, `DEBUG_ENABLE[7:3]`
will read back whatever was last written to them instead of always reading
`0`. Harmless functionally (nothing reads those bits internally) but a
straightforward spec-conformance fix and a one-line-per-register change.

### 2.5 `STATUS[6]`/`STATUS[7]` ("clear on read") is not implemented

Spec §5.7: *"PRBS_ERR and FIFO_ERR are sticky and clear on read."* The RTL
does implement the *sticky* half (`overflow_sticky`/`underflow_sticky` in
`tx_top`/`rx_top`, `sticky_error_reg` in `prbs_checker`), and
`serdesphy_csr_top.v:78-94` correctly ORs/mixes them into `reg_status`. But
nothing clears those sticky bits when the host performs an I2C read of
`0x06` — the only way to clear `PRBS_ERR` today is `RX_ALIGN_RST` (§5.3), and
there is no way to clear the FIFO overflow/underflow sticky bits at all short
of a full reset. `TEST_CHECKLIST.md` REG_035/REG_036 are checked off
(`[X]`), which is inconsistent with what the RTL actually does — worth
double-checking whether the referenced cocotb test actually exercises
clear-on-read or just sticky-set behavior.

*Fix:* needs a `reg_status_read_strobe` from `serdesphy_i2c_slave.v` (a read
of address `0x06` completing) fed back to clear the sticky registers in
`tx_top`/`rx_top`/`prbs_checker`. This is a small but real piece of new
plumbing, not present anywhere today (`reg_write_strobe` exists; there is no
equivalent read-strobe).

### 2.6 `TX_CONFIG`/`RX_CONFIG` polarity and `DATA_SELECT` — verified correct

For completeness: `serdesphy_tx_data_mux.v:87` treats `tx_data_sel==1` as
"select FIFO", matching §5.4 (`0=PRBS, 1=FIFO`) exactly, and
`serdesphy_rx_top.v:381` treats `rx_data_sel==1` as "route PRBS error count
instead of FIFO data", matching §5.4 (`0=FIFO, 1=PRBS status`). No bug here —
called out explicitly because it's easy to mis-flag as backwards on a quick
read.

## 3. Section-by-section conformance

### 3.1 Clock architecture (§4.1)

| Item | Status |
|---|---|
| 24 MHz reference domain | ✅ implemented, used for all CSR/FIFO/word logic |
| 240 MHz TX domain from PLL | ✅ implemented (behavioral VCO always free-runs at 240 MHz in sim) |
| 240 MHz RX domain from CDR | ⚠️ **not actually independent — see Finding 2.2** |
| PLL 10× multiplication, ÷10 feedback divider | ✅ structurally present (`serdesphy_ana_frequency_divider`, counter-based ÷10) |
| PLL lock time 8–10 µs | ⚠️ modeled as a fixed 240-cycle (10 µs @ 24 MHz) counter in `serdesphy_ana_pll.v`'s `STATE_ACQUIRE`, **independent of `vco_trim`/`cp_current`** — see §3.6 |
| PLL jitter 50–100 ps RMS | ❌ not modeled at all (behavioral VCO is a pure fixed-period toggle); no jitter injection anywhere in the digital-only model — expected until the real VCO circuit exists (see `pll/README.md`) |
| VCO tuning range 200–400 MHz | ❌ not modeled — behavioral VCO frequency is fixed at 240 MHz regardless of `vco_trim`/`vco_control` (see §3.6) |

### 3.2 Transmit datapath (§4.2)

| Item | Status |
|---|---|
| Word assembler (2×4-bit → 8-bit over 2 cycles) | ✅ `serdesphy_word_assembler.v`, correct nibble order (low then high) |
| TX FIFO (8×8, full/empty flags, overflow discard) | ✅ `serdesphy_tx_fifo.v` — standard binary-pointer FIFO. Note: spec's "Full threshold: 7 words" table entry is not implemented as an early/almost-full flag; the RTL's `full` only asserts at true 8/8 occupancy. Worth clarifying with the datasheet author whether "7" meant "capacity minus the extra pointer bit" (a documentation artifact) or an intentional early-warning threshold that still needs building. |
| PRBS-7 generator (x⁷+x⁶+1, 8-bit parallel, 24 MHz) | ✅ `serdesphy_prbs_generator.v`, correct polynomial taps (verified against the `prbs_checker`'s matching unrolled LFSR) |
| TX data mux (FIFO vs PRBS, TX_IDLE override) | ✅ `serdesphy_tx_data_mux.v`, correct priority (`tx_idle` overrides both, per §5.2) |
| Manchester encoder (0→10, 1→01) | ✅ `serdesphy_manchester_encoder.v`, matches §4.4 exactly |
| Serializer (16 bits @ 240 MHz, MSB first) | ✅ implemented *inside* `tx_top`'s 240 MHz shift register (not via the orphaned `serdesphy_ana_serializer.v` — see §1) |
| Differential driver (CML, 100 Ω, 400–800 mVpp) | ⚠️ behavioral-only: `serdesphy_ana_tx_differential_driver.v` produces true complementary digital levels with no swing/impedance modeling — expected at this stage, tracked in `tx_driver/README.md` |

### 3.3 Receive datapath (§4.3)

| Item | Status |
|---|---|
| Differential receiver (~10 mV sensitivity, hysteresis) | ⚠️ behavioral-only digital comparator, no analog sensitivity/hysteresis modeling — tracked in `rx_receiver/README.md` |
| CDR (Alexander bang-bang PD) | ⚠️ structurally present (`serdesphy_ana_cdr.v` does sample data on consecutive edges in an Alexander-like pattern) but lock declaration is a fixed cycle count (`STATE_ACQUIRE` counter), not derived from actual phase-error convergence, and its VCO output is bypassed at the PMA boundary (Finding 2.2) |
| Deserializer (16-bit shift @ 240 MHz) | ✅ implemented inside `rx_top`'s serial accumulator (not via the orphaned `serdesphy_ana_deserializer.v`) |
| Manchester decoder (biphase → 8-bit, error detection) | ✅ `serdesphy_manchester_decoder.v`, correctly flags invalid `00`/`11` symbol pairs |
| RX FIFO (8×8, CDC) | ✅ `serdesphy_rx_fifo.v` implements a full gray-code dual-clock FIFO, but is currently instantiated with `wr_clk == rd_clk == clk_24m` in `rx_top` (both `clk_24m`) — the CDC logic is present and correct but not exercising an actual clock-domain crossing today, consistent with Finding 2.2 (there's no independently-clocked recovered domain to cross from yet). |
| Word disassembler (8-bit → 2×4-bit) | ✅ `serdesphy_word_disassembler.v` |
| PRBS checker (single-bit error/word, saturating counter, `RX_ALIGN_RST` clears) | ✅ `serdesphy_prbs_checker.v`, matches §4.3 exactly, LFSR taps verified consistent with the TX generator |

### 3.4 Manchester encoding (§4.4)

Fully matches spec on both encode and decode sides, including the
`00`/`11` invalid-symbol error detection used to drive the RX alignment FSM's
`pattern_detected` signal (`serdesphy_rx_top.v:329-345`).

### 3.5 Register map / I2C (§5, §6)

I2C slave (`serdesphy_i2c_slave.v` + `serdesphy_serialInterface.v`, adapted
from the OpenCores implementation) implements start/stop detection,
debouncing, 7-bit address match against `0x42`, ACK/NAK, and
auto-incrementing register-address read/write per §6.2 — this matches the
spec's transaction format. Debounce/delay lengths (`DEB_I2C_LEN`,
`SCL_DEL_LEN`, `SDA_DEL_LEN`) are parameterized off `CLK_FREQ=24` and look
correctly derived for the 24 MHz system clock.

Gaps found: register defaults (§2.3), reserved-bit masking (§2.4), and
clear-on-read (§2.5) as detailed above. No I2C timing violations found
against §6.1.

### 3.6 PLL closed-loop behavior — the loop isn't actually closed in sim

This is a modeling limitation, not a functional bug, but worth stating
plainly since it affects what current simulation results can and can't
prove: `serdesphy_ana_pll_vco.v` produces a fixed ~240 MHz clock whenever
`enable && rst_n` are true, completely ignoring its `vco_control` input.
`vco_trim` and `cp_current` therefore have **zero effect on the simulated TX
clock frequency** — the charge pump (`serdesphy_ana_pll_charge_pump.v`) is
literally tied to `1'b0` output ("Placeholder... tie to 0"), so the loop
filter's integrator never moves, and even if it did the VCO wouldn't react.
`PLL_LOCK` in `serdesphy_ana_pll.v` is purely a state-machine timer
(`STATE_ACQUIRE` counts to 240 cycles then asserts), not a real
frequency-error convergence check.

This is the expected state for a *digital-only, functional-bring-up*
behavioral model (it correctly gives downstream digital logic a stable 240
MHz clock and a lock pulse with roughly the right latency), but it means:
none of the PLL_CONFIG register's analog knobs (`VCO_TRIM`, `CP_CURRENT`) do
anything observable yet, and no amount of RTL simulation can validate the
real lock-time/jitter/tuning-range specs in §4.1. That validation can only
happen once the real circuit exists (`pll/README.md`) and is simulated in
SPICE, or once a higher-fidelity math model (see `pll/README.md` §"upgrade
path for the behavioral model") replaces the current stub.

## 4. What's left to do (by category)

### 4.1 Digital RTL fixes (small, no new circuits needed)
- [ ] Fix `PLL_LOCK` gating on `tx_en` (Finding 2.1) — **highest priority**, blocks the documented init sequence.
- [ ] Decide the fate of the orphaned `pll_ctrl`/`clock_manager`/`debug_mux`/`analog_debug_buffer` modules — delete or wire in (Finding 2.1/§1).
- [ ] Fix `PLL_CONFIG`/`CDR_CONFIG` reset defaults to `0x68`/`0x14` (Finding 2.3).
- [ ] Mask reserved bits on write for all registers, not just `PHY_ENABLE` (Finding 2.4).
- [ ] Implement clear-on-read for `STATUS[6]`/`STATUS[7]` (Finding 2.5) — needs a new read-strobe signal out of `serdesphy_i2c_slave.v`.
- [ ] Wire the real debug mux (`serdesphy_debug_mux.v` + `serdesphy_ana_analog_debug_buffer.v`) so `DBG_VCTRL`/`DBG_PD`/`DBG_FIFO` (§5.8) actually route `vco_control`/`phase_detector`/FIFO status to `dbg_ana`, instead of `dbg_ana` being a raw config bit.
- [ ] Clarify/implement the TX FIFO "full threshold: 7 words" spec line (§3.2) — either fix the doc or add an early-warning flag.

### 4.2 Architectural work (needs design decisions, not just wiring)
- [ ] Make the CDR clock domain real: remove the `clk_240m_cdr = pll_clk_240m` shortcut (Finding 2.2), re-introduce a real CDC boundary between the recovered clock and the `clk_24m` domain — this is exactly what the orphaned `serdesphy_deserializer_if.v`/`serdesphy_rx_fifo.v`'s dual-clock support are for. This can only be meaningfully finished once the CDR VCO is a real, independently-running oscillator (behavioral or SPICE) — see `cdr_vco/README.md`.
- [ ] Once the CDR domain is real, add a frequency-offset/jitter injection knob to the behavioral CDR VCO so `±2000 ppm` acquisition range and `~1 MHz` tracking bandwidth (§4.3) become simulatable claims instead of aspirational spec text.
- [ ] Add a lightweight loop-gain math model to the behavioral PLL/CDR VCOs (frequency reacts to `vco_control`/`cdr_control` with a configurable Kvco) so lock dynamics respond to `VCO_TRIM`/`CP_CURRENT`/`CDR_GAIN` even before the real analog circuits exist. See `pll/README.md` and `cdr_vco/README.md` for the proposed model.

### 4.3 Analog circuit design (the bulk of remaining work — see per-block plans)
None of `src/analog/*` has a schematic, SPICE testbench, or layout yet — all
are synthesizable-looking Verilog placeholders. Real circuit design work is
needed for:
- PLL: ring VCO, PFD, charge pump, loop filter (see `pll/README.md`)
- TX differential driver: CML output stage with swing control (see `tx_driver/README.md`)
- RX differential receiver: limiting amplifier / CTLE front end (see `rx_receiver/README.md`)
- CDR: Alexander bang-bang phase detector + CDR VCO (see `cdr_vco/README.md`)
- Supporting cells: bias generator, analog debug buffer, loopback switch — lower priority, simpler circuits, can follow the same framework (`02-analog-digital-dual-flow-framework.md`) once the four blocks above establish the pattern.

### 4.4 Verification gaps (from `test/TEST_CHECKLIST.md`)
The checklist itself shows exactly where coverage stands: **POR (10/10),
I2C (11/11), and the full register map (40/40) are checked off** — that part
of the design is well-tested. Everything after that is unchecked:
**Clock/PLL (0/9), TX datapath (0/21), RX datapath (0/19), Loopback (0/5),
Test mode (0/3), Init sequence (0/11), Error conditions (0/7), Corner cases
(0/7)** — 82 of 143 planned tests (57%) don't exist yet. Given the bugs found
in §2 (especially 2.1, which the init-sequence tests would have caught
immediately), closing the **Init Sequence** and **Clock/PLL** categories
first would have the highest bug-per-test-written yield.

## 5. Places that can be improved (non-blocking)

- **Naming consistency**: some status signals are computed in two places with
  different qualifications (`pll_lock` in `pcs.v` vs. the unused, more
  correct version in `pll_ctrl.v`). Once §4.1's cleanup lands, there should
  be exactly one place that computes each externally-visible status bit.
- **`serdesphy_rx_fifo.v` is a fully general dual-clock gray-code FIFO** but
  is only ever instantiated with both clocks tied to `clk_24m`
  (`serdesphy_rx_top.v:125-146`). That's correct-but-wasted generality right
  now; it becomes load-bearing once Finding 2.2 is fixed. Leave as-is, but
  don't "simplify" it back to a single-clock FIFO — it's already built for
  where this design needs to go.
- **`serdesphy_tx_top.v`'s `manchester_error_sticky`** is set to `0` on
  `manchester_encoder_error` (`serdesphy_tx_top.v:276`, should presumably be
  `<= 1'b1`), but since `manchester_encoder_error` is hardwired to `1'b0`
  (line 181, "Manchester encoder doesn't have error output"), this is
  currently unreachable dead logic rather than an active bug. Worth fixing
  opportunistically if that error path is ever wired up.
- **Debug/CSR modules carry OpenCores attribution headers** (`i2c_slave`,
  `registerInterface`, `serialInterface`) — good practice already followed;
  make sure the LICENSE file's terms are compatible when this heads toward
  tapeout (LGPL 2.1 for the OpenCores-derived files vs. the project's own
  Apache-2.0 in `project.v`).
