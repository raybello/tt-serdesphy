# serdesphy_por — Power-On-Reset Controller

**Source:** `src/digital/por/serdesphy_por.v`  
**Clock:** `clk` (24 MHz reference, `clk_ref_24m`)  
**Reset:** `rst_n_in` (external active-low, **asynchronous** to `clk`)

---

## Purpose

Monitors supply-good signals and sequences the release of analog isolation, digital reset,
and analog reset in the correct order after a valid power-up.  Re-sequences from scratch
if any supply is lost at any time.  Ensures the PHY never enters an undefined state due to
partial power.

---

## Port List

| Port | Dir | Width | Description |
|---|---|---|---|
| `dvdd_ok` | I | 1 | 1.8 V digital supply monitor (from IO pad or on-chip comparator) |
| `avdd_ok` | I | 1 | 3.3 V analog supply monitor |
| `rst_n_in` | I | 1 | External active-low reset; asynchronous assertion (glitch-free de-assertion required) |
| `clk` | I | 1 | 24 MHz reference clock |
| `phy_en` | I | 1 | PHY enable from CSR (gates `analog_iso_n` in READY state) |
| `iso_en` | I | 1 | Analog isolation override from CSR (ISO_EN bit) |
| `power_good` | O | 1 | Both supplies stable and sequencing complete |
| `analog_iso_n` | O | 1 | Analog isolation: **0 = isolated**, 1 = connected |
| `digital_reset_n` | O | 1 | Digital domain reset: 0 = in reset, 1 = released |
| `analog_reset_n` | O | 1 | Analog domain reset: 0 = in reset, 1 = released |
| `por_active` | O | 1 | High while FSM is not in STATE_READY |
| `por_complete` | O | 1 | High after first successful sequencing |

---

## Timing Constants (all @ 24 MHz = 41.67 ns/cycle)

| Constant | Value | Time | Purpose |
|---|---|---|---|
| `SUPPLY_STABLE_CYCLES` | 48 | ≈ 2 µs | Debounce `dvdd_ok && avdd_ok` before starting sequencing |
| `RESET_HOLD_CYCLES` | 24 | ≈ 1 µs | Hold time after releasing isolation before releasing digital reset |
| `RELEASE_DELAY_CYCLES` | 12 | ≈ 0.5 µs | Inter-stage delay between digital and analog reset release |

---

## Main FSM

4-state Gray-adjacent encoding (3-bit registers, only 4 values used).

| State | Value | Description |
|---|---|---|
| `STATE_RESET` | `3'd0` | All held in reset; waiting for `supplies_ok` |
| `STATE_WAIT_SUPPLY` | `3'd1` | Debouncing `supplies_ok` for 48 cycles |
| `STATE_SEQUENCING` | `3'd2` | Releasing resets in order |
| `STATE_READY` | `3'd3` | Normal operation; monitoring supplies |

### Transition Table

| From | Condition | To | Notes |
|---|---|---|---|
| `RESET` | `supplies_ok` | `WAIT_SUPPLY` | Loads `SUPPLY_STABLE_CYCLES` timer |
| `WAIT_SUPPLY` | `!supplies_ok` | `RESET` | Supply glitch during debounce |
| `WAIT_SUPPLY` | `timer == 0` | `SEQUENCING` | Supply confirmed stable |
| `SEQUENCING` | `!supplies_ok` | `RESET` | Supply lost mid-sequence |
| `SEQUENCING` / `SEQ_DONE` | `timer == 0` | `READY` | All resets released |
| `READY` | `!supplies_ok` | `RESET` | Live supply monitoring |
| `default` | — | `RESET` | Safe fallback |

---

## Sequencing Sub-FSM (inside STATE_SEQUENCING)

2-bit counter `seq_step`.  Each sub-state waits for `timer == 0` before acting.

| Step | Name | Action | Next timer |
|---|---|---|---|
| `2'd0` | `SEQ_RELEASE_ISO` | `analog_iso_n_reg ← ~iso_en` | `RESET_HOLD_CYCLES` (24) |
| `2'd1` | `SEQ_RELEASE_DIGITAL` | `digital_reset_n_reg ← 1` | `RELEASE_DELAY_CYCLES` (12) |
| `2'd2` | `SEQ_RELEASE_ANALOG` | `analog_reset_n_reg ← 1` | `RELEASE_DELAY_CYCLES` (12) |
| `2'd3` | `SEQ_DONE` | `power_good_reg ← 1`, `por_complete_reg ← 1` | (→ STATE_READY) |

### Release Timeline

```
supplies_ok asserted
  ↓  48 cycles (2 µs)    supply debounce
analog_iso_n released (→ 1, unless iso_en=1)
  ↓  24 cycles (1 µs)    hold
digital_reset_n released (→ 1)
  ↓  12 cycles (0.5 µs)  delay
analog_reset_n released (→ 1)
  ↓  12 cycles (0.5 µs)  delay
power_good / por_complete asserted
  → STATE_READY
```

Total minimum time from `supplies_ok` to `por_complete`: ≈ 3.5 µs.

---

## READY State Behavior

In `STATE_READY`:
- `por_complete_reg` remains asserted (never de-asserted unless reset).
- `power_good_reg` follows `supplies_ok` combinationally (single-cycle lag on loss).
- `analog_iso_n_reg` tracks `~iso_en` (CSR-controlled isolation in READY state).
- Supply loss (`!supplies_ok`) immediately returns to `STATE_RESET`.

---

## Output Assignments

| Output | Source |
|---|---|
| `power_good` | `power_good_reg` |
| `analog_iso_n` | `analog_iso_n_reg` |
| `digital_reset_n` | `digital_reset_n_reg` |
| `analog_reset_n` | `analog_reset_n_reg` |
| `por_active` | `(state != STATE_READY)` — combinational |
| `por_complete` | `por_complete_reg` |

---

## Interactions

| Signal | Destination |
|---|---|
| `digital_reset_n` | `serdesphy_pcs` → combined with `rst_n_in` → `rst_n_24m`, `rst_n_240m_tx`, `rst_n_240m_rx` via `serdesphy_reset_synchronizer` |
| `analog_reset_n` | `serdesphy_pma` → resets PLL, CDR, TX driver, RX receiver |
| `analog_iso_n` | `serdesphy_pma` → gates analog bias currents |
| `por_complete` | `serdesphy_pcs` → qualified `phy_ready` top-level output |
| `phy_en`, `iso_en` | ← `serdesphy_csr_top` (PHY_ENABLE[0], PHY_ENABLE[1]) |

---

## Known Limitations

- `rst_n_in` is described as asynchronous assertion; the FSM uses it directly as the
  `negedge rst_n_in` async reset.  De-assertion must be synchronous to `clk` to avoid
  metastability in the FSM flip-flops (this is the caller's responsibility —
  `serdesphy_pcs` must guarantee de-assertion is synchronous).
- Supply monitors `dvdd_ok` / `avdd_ok` are external binary signals with no internal
  glitch filter beyond the 48-cycle debounce in `STATE_WAIT_SUPPLY`; a 1-cycle glitch
  in `STATE_READY` immediately re-triggers sequencing.
- `phy_en` is read in STATE_SEQUENCING (`SEQ_RELEASE_ISO`) to gate `analog_iso_n`, but
  `phy_en` may not be valid until digital reset is released — if `phy_en` reads as 0
  when `SEQ_RELEASE_ISO` fires, isolation is held asserted, blocking subsequent reset
  releases.  The documented init sequence mitigates this by writing PHY_ENABLE=0x01
  before POR, but the RTL has no guard.
