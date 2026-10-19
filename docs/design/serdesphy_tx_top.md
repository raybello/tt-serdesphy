# serdesphy_tx_top — Transmit Datapath and Controller

**Source:** `src/digital/tx/serdesphy_tx_top.v`  
**Clocks:** `clk_24m`, `clk_240m_tx`  
**Resets:** `rst_n_24m` (active-low, 24 MHz domain), `rst_n_240m_tx` (active-low, 240 MHz domain)

---

## Purpose

Integrates the complete transmit pipeline: word assembler → TX FIFO → TX data mux →
Manchester encoder → 240 MHz serial shift register.  Houses the TX controller FSM and
all TX sticky-error logic.  Acts as the boundary between the 24 MHz CSR/data plane and
the 240 MHz serial output plane.

---

## Port List

| Port | Dir | Width | Clock domain | Description |
|---|---|---|---|---|
| `clk_24m` | I | 1 | — | 24 MHz system clock |
| `clk_240m_tx` | I | 1 | — | 240 MHz TX PLL clock |
| `rst_n_24m` | I | 1 | — | Active-low synchronous reset, 24 MHz domain |
| `rst_n_240m_tx` | I | 1 | — | Active-low synchronous reset, 240 MHz domain |
| `tx_en` | I | 1 | 24M | TX global enable (from TX_CONFIG[0]) |
| `tx_fifo_en` | I | 1 | 24M | TX FIFO enable (from TX_CONFIG[1]) |
| `tx_prbs_en` | I | 1 | 24M | PRBS generator enable (from TX_CONFIG[2]) |
| `tx_idle` | I | 1 | 24M | Force idle / zero output (from TX_CONFIG[3]) |
| `tx_data_sel` | I | 1 | 24M | Data source: `0` = PRBS, `1` = FIFO (from DATA_SELECT[0]) |
| `tx_data[3:0]` | I | 4 | 24M | 4-bit nibble from external host |
| `tx_valid` | I | 1 | 24M | Nibble valid strobe from host |
| `clk_240m_tx_en` | I | 1 | 24M | PLL lock gate: enables 240 MHz serial path |
| `status_read_clear` | I | 1 | 24M | Clears overflow/underflow sticky bits (I²C STATUS read) |
| `tx_serial_data` | O | 1 | 240M TX | Serialized Manchester bit to PMA |
| `tx_serial_valid` | O | 1 | 240M TX | Serial output valid (deasserted during idle) |
| `tx_idle_pattern` | O | 1 | 240M TX | Driven high when shift register is idle |
| `tx_fifo_full` | O | 1 | 24M | TX FIFO at capacity |
| `tx_fifo_empty` | O | 1 | 24M | TX FIFO empty |
| `tx_overflow` | O | 1 | 24M | Sticky: overflow since last STATUS read |
| `tx_underflow` | O | 1 | 24M | Sticky: underflow since last STATUS read |
| `tx_active` | O | 1 | 24M | TX FSM is in STARTING or ACTIVE state |
| `tx_error` | O | 1 | 24M | TX FSM is in ERROR state (or Manchester error sticky) |

---

## Sub-module Instances

| Instance | Module | Role |
|---|---|---|
| `u_word_assembler` | `serdesphy_word_assembler` | Two-cycle 4→8 bit packer |
| `u_tx_fifo` | `serdesphy_tx_fifo` | 8-deep × 8-bit single-clock FIFO |
| `u_prbs_generator` | `serdesphy_prbs_generator` | PRBS-7 source |
| `u_tx_data_mux` | `serdesphy_tx_data_mux` | FIFO / PRBS / idle selector |
| `u_manchester_encoder` | `serdesphy_manchester_encoder` | 8-bit → 16-bit biphase |

---

## Datapath Description

### 24 MHz pipeline (combinational/registered)

```
tx_data[3:0] + tx_valid
  → word_assembler (DDR: rise=low nibble, fall=high nibble → 8-bit word, 1-cycle latency)
  → tx_fifo       (8 words deep; pop on mux_fifo_ready)
  → tx_data_mux   (selects FIFO, PRBS, or idle)
  → manchester_encoder (8-bit → 16-bit biphase, 1-cycle latency)
  → manchester_encoder_out[15:0] / manchester_encoder_valid
                                 (written into 240 MHz shift register)
```

`tx_valid` is a rising-edge strobe.  When asserted, `tx_data[3:0]` carries the low nibble
on the rising edge and the high nibble on the falling edge (DDR convention).  Both edges
must be stable for the full half-period.  Gating condition: `tx_valid && tx_en && tx_fifo_en`.

### 240 MHz shift register (in `tx_top` directly — not via `serdesphy_serializer_if`)

```verilog
// On manchester_encoder_valid && serial_bit_count == 0:
serial_shift_reg ← manchester_encoder_out[14:0] (pre-shifted)
serial_bit_count ← 15
tx_serial_data   ← manchester_encoder_out[15]  // MSB first

// Each subsequent cycle while serial_bit_count > 0:
serial_shift_reg ← {serial_shift_reg[14:0], 1'b0}
tx_serial_data   ← serial_shift_reg[15]
serial_bit_count ← serial_bit_count - 1
```

The shift register is gated by `clk_240m_tx_en`; it drives zeros when `tx_idle` or
when no word is loaded.

**Note:** `serdesphy_ana_serializer.v` is orphaned — the serializer is this inline
shift register running at 240 MHz.

---

## TX Controller FSM

Clocked by `clk_24m`.  3-bit binary encoding.

| State | Enc | Entry condition | Actions |
|---|---|---|---|
| `DISABLED` | `000` | Reset, or `tx_en=0 \|\| clk_240m_tx_en=0` | `tx_active ← 0` |
| `IDLE` | `001` | `tx_en && clk_240m_tx_en` from DISABLED | Waits for data or forced idle |
| `STARTING` | `010` | FIFO/PRBS data arrives in IDLE | `tx_active ← 1`; waits for `manchester_encoder_valid` |
| `ACTIVE` | `011` | `manchester_encoder_valid` in STARTING | Normal transmit |
| `STOPPING` | `100` | `tx_en` or `clk_240m_tx_en` deasserts in ACTIVE | Drains encoder |
| `ERROR` | `101` | `error_count` saturates at 7 | `tx_error_reg ← 1` |

Transition summary:

```
DISABLED → IDLE        : tx_en && clk_240m_tx_en
IDLE     → DISABLED    : !tx_en || !clk_240m_tx_en
IDLE     → STARTING    : (fifo word ready) || (prbs data ready)
STARTING → ACTIVE      : manchester_encoder_valid
ACTIVE   → STOPPING    : !tx_en || !clk_240m_tx_en
ACTIVE   → IDLE        : tx_idle
ACTIVE   → ERROR       : error_count == 7
STOPPING → DISABLED    : !manchester_encoder_valid (encoder drained)
ERROR    → DISABLED    : !tx_en  (tx_error_reg cleared on same edge)
default  → ERROR       : illegal encoding
```

**Error counter** (`error_count[2:0]`): increments on
`manchester_encoder_error || tx_fifo_underflow_wire`; enters ERROR at count 7.  Cleared
on `ERROR → DISABLED`.

**Known behavioral note:** `manchester_encoder_error` is hardwired `1'b0` in the current
implementation — the encoder has no independent error output.  The error counter therefore
only increments on FIFO underflow.

---

## Sticky Error Registers

| Register | Set by | Cleared by |
|---|---|---|
| `overflow_sticky` | `tx_fifo_overflow_wire` | `status_read_clear` |
| `underflow_sticky` | `tx_fifo_underflow_wire` | `status_read_clear` |
| `manchester_error_sticky` | `manchester_encoder_error` (dead code — `1'b0`) | Never (see bug note) |

**Bug (line 285):** `if (manchester_encoder_error) manchester_error_sticky <= 1'b0;`
should be `<= 1'b1`.  Dead code today (encoder error is hardwired 0).

`status_read_clear` takes priority over a same-cycle set: a concurrent overflow and STATUS
read clears the sticky rather than latching a new error.

`tx_error` is `tx_error_reg || manchester_error_sticky`.

---

## Timing

| Path | Latency |
|---|---|
| `tx_valid` → `word_assembler_valid` | 1 × `clk_24m` cycle (DDR: both nibbles captured in one cycle) |
| `word_assembler_valid` → FIFO pop | 1 `clk_24m` cycle (registered read) |
| FIFO pop → `manchester_encoder_valid` | 1 `clk_24m` cycle (encoder pipeline) |
| `manchester_encoder_valid` → first serial bit | Captured next `clk_240m_tx` edge |
| Full word serialized | 16 × (1/240 MHz) ≈ 66.7 ns |

---

## Known Limitations

- Manchester encoder error path is a dead stub; `tx_error` is currently only driven by the
  TX FSM `ERROR` state or `tx_fifo_underflow`.
- `serial_bit_count` is 5 bits wide but only ever reaches 15; bit 4 is always 0.
- `fifo_read_en` (registered) is computed in `tx_top` but `tx_fifo` reads are controlled
  by the mux's `mux_fifo_ready` signal — the `fifo_read_en` register is unused.
