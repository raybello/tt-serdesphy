# serdesphy_rx_top — Receive Datapath and Controller

**Source:** `src/digital/rx/serdesphy_rx_top.v`  
**Clocks:** `clk_240m_rx` (CDR-recovered, fast domain), `clk_24m` (system domain)  
**Resets:** `rst_n_240m_rx`, `rst_n_24m`

---

## Purpose

Integrates the complete receive pipeline: serial accumulator → Manchester alignment FSM →
Manchester decoder → RX FIFO (CDC boundary) → word disassembler.  Also integrates the
PRBS checker.  Houses both the alignment FSM (240 MHz domain) and the RX controller FSM
(24 MHz domain).

---

## Port List

| Port | Dir | Width | Clock domain | Description |
|---|---|---|---|---|
| `clk_24m` | I | 1 | — | 24 MHz system clock |
| `clk_240m_rx` | I | 1 | — | 240 MHz CDR-recovered clock |
| `rst_n_24m` | I | 1 | — | Active-low reset, 24 MHz domain |
| `rst_n_240m_rx` | I | 1 | — | Active-low reset, 240 MHz domain |
| `rx_en` | I | 1 | 24M | RX global enable (RX_CONFIG[0]) |
| `rx_fifo_en` | I | 1 | 24M | RX FIFO enable (RX_CONFIG[1]) |
| `rx_prbs_chk_en` | I | 1 | 24M | PRBS checker enable (RX_CONFIG[2]) |
| `rx_align_rst` | I | 1 | 24M | Self-clearing reset for alignment FSM + PRBS counter |
| `rx_data_sel` | I | 1 | 24M | Output mux: `0` = FIFO data, `1` = PRBS error count |
| `rx_serial_data` | I | 1 | 240M RX | Serial bit from deserializer/loopback |
| `rx_serial_valid` | I | 1 | 240M RX | Deserializer active (not per-word framing) |
| `rx_serial_error` | I | 1 | 240M RX | Deserializer error condition |
| `clk_240m_rx_en` | I | 1 | 24M | CDR lock gate |
| `status_read_clear` | I | 1 | 24M | Clears sticky overflow/underflow on I²C STATUS read |
| `rx_data[3:0]` | O | 4 | 24M | Received nibble (or PRBS error count LSBs) |
| `rx_valid` | O | 1 | 24M | Nibble valid strobe |
| `rx_fifo_full` | O | 1 | 24M | RX FIFO full |
| `rx_fifo_empty` | O | 1 | 24M | RX FIFO empty |
| `rx_overflow` | O | 1 | 24M | Sticky: overflow since last STATUS read |
| `rx_underflow` | O | 1 | 24M | Sticky: underflow since last STATUS read |
| `rx_active` | O | 1 | 24M | FSM in ACTIVE state |
| `rx_error` | O | 1 | 24M | FSM in ERROR state (or sticky Manchester/serial error) |
| `rx_aligned` | O | 1 | — | Manchester alignment achieved (crosses to 24M asynchronously) |
| `prbs_err` | O | 1 | 240M RX | PRBS error pulse (combinational from checker) |

---

## Sub-module Instances

| Instance | Module | Clock | Role |
|---|---|---|---|
| `u_manchester_decoder` | `serdesphy_manchester_decoder` | `clk_240m_rx` | 16-bit → 8-bit |
| `u_rx_fifo` | `serdesphy_rx_fifo` | wr=`clk_240m_rx`, rd=`clk_24m` | CDC FIFO |
| `u_word_disassembler` | `serdesphy_word_disassembler` | `clk_24m` | 8→4 nibble split |
| `u_prbs_checker` | `serdesphy_prbs_checker` | `clk_240m_rx` | PRBS-7 verify |

---

## Clock Domain Structure

```
clk_240m_rx domain:
  serial accumulator (sliding window)
  Manchester alignment FSM
  serdesphy_manchester_decoder
  serdesphy_prbs_checker
  RX FIFO (write side)

CDC boundary:
  serdesphy_rx_fifo  [gray-code dual-clock pointers]

clk_24m domain:
  RX FIFO (read side)
  serdesphy_word_disassembler
  RX Controller FSM
  Sticky error registers
```

**CDC note:** `rx_aligned_reg` is driven in the `clk_240m_rx` domain and read by the RX
controller FSM in the `clk_24m` domain.  There is no explicit 2-FF synchronizer on this
crossing in the current RTL.  In the current behavioral simulation
(`clk_240m_rx = clk_240m_tx`), this is benign; a real independent CDR clock requires a
synchronizer here.

---

## Serial Accumulator (clk_240m_rx domain)

A 16-bit sliding shift register shifted on every `clk_240m_rx` cycle (when
`clk_240m_rx_en && rx_en && rx_serial_valid && !rx_serial_error`):

```
serial_shift_reg ← {serial_shift_reg[14:0], rx_serial_data}

if valid_manchester_word(serial_shift_reg):
    manchester_word_reg   ← serial_shift_reg
    manchester_word_valid ← 1  (one-cycle pulse)
```

`valid_manchester_word(w)`: all eight 2-bit pairs `w[2i+1:2i]` must differ (XOR = 1).
Patterns `00` and `11` are invalid Manchester.

The check runs **every cycle** — no fixed 16-cycle stride.  Idle gaps on the line are
all-zero bits (invalid Manchester), so a window spanning a word boundary or an idle gap
reliably fails until it falls entirely within one valid word.  This avoids the alignment
drift that a fixed-stride scheme suffers under a CDR clock that does not advance in
lockstep with the TX PLL.

---

## Alignment FSM (clk_240m_rx domain)

Three states are declared; only two are reachable:

| State | Encoding | Reachable |
|---|---|---|
| `ALIGN_STATE_SEARCH` | `2'b00` | Yes |
| `ALIGN_STATE_VERIFY` | `2'b01` | **No** — declared, never entered |
| `ALIGN_STATE_LOCKED` | `2'b10` | Yes |

Effective FSM:

```
SEARCH → LOCKED  : first manchester_word_valid pulse
LOCKED → SEARCH  : no_valid_word_count reaches NO_VALID_WORD_TIMEOUT (1000 cycles ≈ 4.17 µs)
default → SEARCH : any illegal encoding
```

`no_valid_word_count` resets to 0 on each `manchester_word_valid` pulse (received word
resets the timer). Counts consecutive cycles with no valid word.

Reset: `rx_align_rst`, `rx_state == DISABLED`, or `rx_state == ERROR` all force
SEARCH and clear `rx_aligned_reg`.

---

## Manchester Decoder and FIFO Write Path

The decoder receives `manchester_word_reg` with a `data_valid` pulse gated only by
`rx_en` (not by alignment state — see inline comment in RTL).  This is correct because
`manchester_word_valid` is already pre-validated; gating on alignment would discard the
word that triggers alignment.

The FIFO write path:
```
wr_valid = manchester_decoder_valid && !manchester_decoder_error
```
Errored windows are excluded.  Without this guard, idle zeros would flood the 8-entry
FIFO every 66.7 ns (once per 16 fast cycles) before the host can drain them.

---

## RX Controller FSM (clk_24m domain)

3-bit binary encoding.

| State | Enc | Entry | Actions |
|---|---|---|---|
| `DISABLED` | `000` | Reset, or `rx_en=0 \|\| clk_240m_rx_en=0` | `rx_active ← 0` |
| `ALIGNING` | `001` | From DISABLED when `rx_en && clk_240m_rx_en` | Waits for `rx_aligned_reg` |
| `ACQUIRING` | `010` | `rx_aligned_reg` asserts in ALIGNING | Waits for first `manchester_data_valid` |
| `ACTIVE` | `011` | `manchester_data_valid` in ACQUIRING | `rx_active ← 1`; normal receive |
| `ERROR` | `100` | `error_count == 7` | `rx_error_reg ← 1` |

Transition summary:
```
DISABLED   → ALIGNING   : rx_en && clk_240m_rx_en
ALIGNING   → DISABLED   : !rx_en || !clk_240m_rx_en
ALIGNING   → ACQUIRING  : rx_aligned_reg
ACQUIRING  → DISABLED   : !rx_en || !clk_240m_rx_en
ACQUIRING  → ACTIVE     : manchester_data_valid
ACTIVE     → DISABLED   : !rx_en || !clk_240m_rx_en  (rx_active ← 0)
ACTIVE     → ALIGNING   : !rx_aligned_reg (realignment needed)
ACTIVE     → ERROR      : error_count == 7
ERROR      → DISABLED   : !rx_en
default    → ERROR
```

Error sources counted toward `error_count[2:0]`: `manchester_decoder_error`,
`rx_fifo_overflow_wire`, `rx_serial_error`, `prbs_error_wire`.

---

## PRBS Checker

Instantiated in `clk_240m_rx` domain (consumes `manchester_decoder_valid`, a fast-domain
pulse).  Polynomial x⁷ + x⁶ + 1.

- `prbs_error` — combinational pulse per bad byte
- `error_count[7:0]` — saturating 8-bit counter (reset by `rx_align_rst`)
- `sticky_error_reg` — cleared by `status_read_clear`

---

## RX Output Mux

| `rx_data_sel` | `rx_data[3:0]` | `rx_valid` |
|---|---|---|
| `0` | `word_disassembler_out[3:0]` | `word_disassembler_valid` |
| `1` | `prbs_error_count[3:0]` (lower nibble) | `manchester_decoder_valid` |

In PRBS status mode (`rx_data_sel=1`), `rx_valid` pulses once per decoded Manchester word
(every 16 fast cycles ≈ 66.7 ns), giving the host a snapshot of the lower nibble of the
error counter at each word boundary.

---

## Sticky Error Registers (clk_24m domain)

| Register | Set by | Cleared by |
|---|---|---|
| `overflow_sticky` | `rx_fifo_overflow_wire` | `status_read_clear` |
| `underflow_sticky` | `rx_fifo_underflow_wire` | `status_read_clear` |
| `manchester_error_sticky` | `manchester_decoder_error` | Never cleared (no clear path in RTL) |
| `serial_error_sticky` | `rx_serial_error` | Never cleared |

`rx_error = rx_error_reg || manchester_error_sticky || serial_error_sticky`.

**Note:** `manchester_error_sticky` and `serial_error_sticky` have no clear path — once
set, `rx_error` stays asserted until `rst_n_24m`.  This is a known limitation; a
`status_read_clear` path should be added to both.

---

## Timing

| Path | Domain | Latency |
|---|---|---|
| Serial bit in → `manchester_word_valid` | 240M RX | 1 cycle (sliding window) |
| `manchester_word_valid` → decoded byte | 240M RX | 1 cycle (decoder pipeline) |
| Decoded byte written to FIFO | 240M RX | 1 cycle (FIFO write) |
| FIFO read + word disassembler | 24M | 1 cycle (DDR: both nibbles in one cycle) |
| `rx_valid` rising edge; host captures rise nibble + fall nibble | 24M | — |
