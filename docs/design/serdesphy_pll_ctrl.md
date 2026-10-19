# serdesphy_pll_ctrl — PLL Lock Qualifier

**Source:** `src/digital/pll/serdesphy_pll_ctrl.v`  
**Clock:** `clk_ref_24m` (24 MHz)  
**Reset:** `rst_n` (active-low, asynchronous)

---

## Purpose

Produces a qualified, hysteresis-filtered `pll_lock` signal from the behavioral PLL's
raw lock output.  Exists to decouple `STATUS[0].PLL_LOCK` from the TX serializer's
enable state — a bug in earlier revisions aliased PLL lock to the serializer's "ready"
signal, making it impossible to poll PLL_LOCK before enabling TX (as the documented init
sequence requires).

---

## Port List

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk_ref_24m` | I | 1 | 24 MHz reference clock |
| `rst_n` | I | 1 | Active-low asynchronous reset |
| `phy_en` | I | 1 | PHY global enable (PHY_ENABLE[0]) |
| `pll_lock_raw` | I | 1 | Raw lock signal from `serdesphy_ana_pll` |
| `pll_vco_ok` | I | 1 | VCO operating range (currently aliased to `pll_lock_raw` in PMA) |
| `pll_cp_ok` | I | 1 | Charge pump health (not independently driven in PMA) |
| `pll_lock` | O | 1 | Qualified, debounced PLL lock |
| `pll_ready` | O | 1 | Same as `pll_lock` (functional alias) |
| `pll_status[7:0]` | O | 8 | Diagnostic: `{4'b0, pll_cp_ok, pll_vco_ok, pll_lock_raw, phy_en}` |
| `pll_error` | O | 1 | PLL error flag — **hardwired `0`** (see below) |

---

## Parameters / Constants

| Constant | Value | Time @ 24 MHz |
|---|---|---|
| `LOCK_COUNT_MAX` | 16 | 4 cycles ≈ 167 ns extra debounce |
| `UNLOCK_COUNT` | 16 | 240 cycles ≈ 10 µs before de-asserting |

---

## Lock Qualification Condition

```verilog
wire pll_healthy = phy_en && pll_lock_raw && pll_vco_ok && pll_cp_ok;
```

In the current PMA: `pll_vco_ok = pll_lock_raw` and `pll_cp_ok = 1'b0`... 

Wait — checking PMA behavioral model: `pll_cp_ok` is driven as `pll_cp_ok_wire` from
`serdesphy_ana_pll`.  In practice the behavioral PLL drives `pll_cp_ok` to `1` once
locked.  So `pll_healthy` effectively becomes `phy_en && pll_lock_raw`.

---

## FSM

3-state binary encoding.

| State | Encoding | Description |
|---|---|---|
| `LOCK_STATE_UNLOCKED` | `2'b00` | PLL not yet locked |
| `LOCK_STATE_ACQUIRING` | `2'b01` | Saw `pll_healthy`; counting debounce cycles |
| `LOCK_STATE_LOCKED` | `2'b10` | Qualified lock declared |

### Transition Table

| From | Condition | To | Actions |
|---|---|---|---|
| `UNLOCKED` | `pll_healthy` | `ACQUIRING` | `lock_counter ← 0` |
| `ACQUIRING` | `pll_healthy && lock_counter < LOCK_COUNT_MAX` | `ACQUIRING` | `lock_counter++` |
| `ACQUIRING` | `pll_healthy && lock_counter == LOCK_COUNT_MAX` | `LOCKED` | `pll_lock_reg ← 1`, `pll_ready_reg ← 1` |
| `ACQUIRING` | `!pll_healthy` | `UNLOCKED` | `counters ← 0` |
| `LOCKED` | `!phy_en` | `UNLOCKED` | `pll_lock_reg ← 0`, `pll_ready_reg ← 0` (immediate) |
| `LOCKED` | `phy_en && !pll_healthy && unlock_counter < UNLOCK_COUNT` | `LOCKED` | `unlock_counter++` |
| `LOCKED` | `phy_en && !pll_healthy && unlock_counter == UNLOCK_COUNT` | `UNLOCKED` | `pll_lock_reg ← 0`, `pll_ready_reg ← 0` |
| `LOCKED` | `pll_healthy` | `LOCKED` | `unlock_counter ← 0` |
| `default` | any | `UNLOCKED` | — |

### Key Behaviors

- `phy_en` de-asserted in LOCKED → **immediate** transition to UNLOCKED (no hysteresis
  on the enable path, only on the loss-of-lock path).
- Brief `pll_healthy` glitches in LOCKED state: counted by `unlock_counter`; 240
  consecutive cycles of unhealthy signal needed before lock is dropped.
- `LOCK_COUNT_MAX = 4` was corrected from a prior value of 2400 — the original counted a
  full 100 µs acquisition loop on top of the PLL's own 10 µs timer, causing STATUS[0] to
  never assert during normal operation.

---

## pll_error Rationale

`pll_error` is hardwired `0` because in the current PMA `pll_vco_ok` is aliased to
`pll_lock_raw` (not an independent VCO-health signal).  An earlier version declared a
fault when `phy_en && !pll_vco_ok`, which latched `pll_error = 1` for the entire 10 µs
acquisition window on every startup (VCO is naturally "not OK" while acquiring).  The
fault path will be restored once the PMA exposes a genuinely independent VCO range
indicator.

---

## Interactions

| Signal | Direction | Destination |
|---|---|---|
| `pll_lock` | O → | `serdesphy_csr_top` → STATUS[0]; `serdesphy_pcs` → `clk_240m_tx_en`; `serdesphy_por` (informational) |
| `pll_ready` | O → | `serdesphy_pcs` (alias of `pll_lock`) |
| `phy_en` | ← I | `serdesphy_csr_top.phy_en` (PHY_ENABLE[0]) |
| `pll_lock_raw` | ← I | `serdesphy_pma.pll_lock_raw` (behavioral PLL counter) |

---

## Known Limitations

- `pll_vco_ok` and `pll_cp_ok` are not independently sourced from the PMA; the
  qualification condition reduces to `phy_en && pll_lock_raw`.
- `pll_error` is permanently 0; no fault reporting until PMA exposes real health signals.
- `pll_status[7:0]` is a diagnostic byte but is not mapped to any CSR read path in the
  current `serdesphy_csr_top`.
