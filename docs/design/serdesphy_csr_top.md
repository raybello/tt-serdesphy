# serdesphy_csr_top — Configuration and Status Register Top

**Source:** `src/digital/csr/serdesphy_csr_top.v`  
**Clock:** `clk` (24 MHz system clock)  
**Reset:** `rst_n` (active-low)

---

## Purpose

Glue layer between the I²C slave and all PHY control/status signals.  Instantiates the
I²C slave, assembles the STATUS register from live inputs, decodes write registers into
individual control signals, and generates the `status_read_pulse` clear-on-read strobe.

This module contains **no state registers** — all register state lives in
`serdesphy_i2c_slave` (via `serdesphy_registerInterface`).  `serdesphy_csr_top` is a
purely combinational decode and mux layer.

---

## Port List

### Clocking and I²C Physical

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | I | 1 | 24 MHz reference clock |
| `rst_n` | I | 1 | Active-low reset |
| `sda_in` | I | 1 | SDA from IO pad |
| `sda_out` | O | 1 | SDA to IO pad |
| `sda_oe` | O | 1 | SDA output enable, active-high |
| `scl` | I | 1 | SCL from IO pad |

### Control Outputs (to PHY sub-blocks)

| Port | Dir | Width | Source register | Bit(s) |
|---|---|---|---|---|
| `phy_en` | O | 1 | PHY_ENABLE (0x00) | [0] |
| `iso_en` | O | 1 | PHY_ENABLE (0x00) | [1] |
| `tx_en` | O | 1 | TX_CONFIG (0x01) | [0] |
| `tx_fifo_en` | O | 1 | TX_CONFIG (0x01) | [1] |
| `tx_prbs_en` | O | 1 | TX_CONFIG (0x01) | [2] |
| `tx_idle` | O | 1 | TX_CONFIG (0x01) | [3] |
| `rx_en` | O | 1 | RX_CONFIG (0x02) | [0] |
| `rx_fifo_en` | O | 1 | RX_CONFIG (0x02) | [1] |
| `rx_prbs_chk_en` | O | 1 | RX_CONFIG (0x02) | [2] |
| `rx_align_rst` | O | 1 | RX_CONFIG (0x02) | [3] |
| `tx_data_sel` | O | 1 | DATA_SELECT (0x03) | [0] |
| `rx_data_sel` | O | 1 | DATA_SELECT (0x03) | [1] |
| `vco_trim[3:0]` | O | 4 | PLL_CONFIG (0x04) | [3:0] |
| `cp_current[1:0]` | O | 2 | PLL_CONFIG (0x04) | [5:4] |
| `pll_rst` | O | 1 | PLL_CONFIG (0x04) | [6] |
| `pll_bypass` | O | 1 | PLL_CONFIG (0x04) | [7] |
| `cdr_gain[2:0]` | O | 3 | CDR_CONFIG (0x05) | [2:0] |
| `cdr_fast_lock` | O | 1 | CDR_CONFIG (0x05) | [3] |
| `cdr_rst` | O | 1 | CDR_CONFIG (0x05) | [4] |
| `dbg_vctrl` | O | 1 | DEBUG_ENABLE (0x07) | [0] |
| `dbg_pd` | O | 1 | DEBUG_ENABLE (0x07) | [1] |
| `dbg_fifo` | O | 1 | DEBUG_ENABLE (0x07) | [2] |
| `dbg_ana` | O | 1 | DEBUG_ENABLE (0x07) | **[3]** |

### Status Inputs (from PHY sub-blocks)

| Port | Dir | Source |
|---|---|---|
| `pll_lock` | I | `serdesphy_pll_ctrl` |
| `cdr_lock` | I | PMA CDR |
| `tx_fifo_full` | I | `serdesphy_tx_top` |
| `tx_fifo_empty` | I | `serdesphy_tx_top` |
| `tx_overflow` | I | `serdesphy_tx_top` (sticky) |
| `tx_underflow` | I | `serdesphy_tx_top` (sticky) |
| `rx_fifo_full` | I | `serdesphy_rx_top` |
| `rx_fifo_empty` | I | `serdesphy_rx_top` |
| `rx_overflow` | I | `serdesphy_rx_top` (sticky) |
| `rx_underflow` | I | `serdesphy_rx_top` (sticky) |
| `prbs_err` | I | `serdesphy_rx_top` (sticky) |

### Clear-on-Read

| Port | Dir | Description |
|---|---|---|
| `status_read_pulse` | O | 1 `clk` cycle pulse when I²C reads STATUS (0x06) |

---

## Internal Structure

### I²C Slave (`serdesphy_i2c_slave`)

The I²C slave (`serdesphy_i2c_slave`) contains two sub-modules:

- `serdesphy_registerInterface` — holds the 8 register values, updates on writes
- `serdesphy_serialInterface` — I²C bit-level state machine (start/stop/ACK/NAK)

The slave exposes `reg_read_strobe + reg_read_addr` and `reg_write_strobe + reg_write_addr`
for the clear-on-read logic.

### STATUS Register Assembly (combinational)

```verilog
reg_status = {
    fifo_err,        // [7]  tx_overflow || tx_underflow || rx_overflow || rx_underflow
    prbs_err,        // [6]  from rx_top (already sticky in prbs_checker)
    rx_fifo_empty,   // [5]
    rx_fifo_full,    // [4]
    tx_fifo_empty,   // [3]
    tx_fifo_full,    // [2]
    cdr_lock,        // [1]
    pll_lock         // [0]
};
```

`reg_status` is a wire fed directly to the I²C slave's status port — no register stage.
Reads always see the live combinational value.

### Clear-on-Read Logic

```verilog
assign status_read_pulse = reg_read_strobe && (reg_read_addr[2:0] == 3'h6);
```

`status_read_pulse` fans out to:
- `serdesphy_tx_top.status_read_clear` → clears `overflow_sticky`, `underflow_sticky`
- `serdesphy_rx_top.status_read_clear` → clears `overflow_sticky`, `underflow_sticky`
- `serdesphy_prbs_checker.clear_sticky` → clears `sticky_error_reg`

---

## Debug Output (dbg_ana)

```verilog
assign dbg_ana = reg_debug_enable[3];
```

**Implementation note:** `dbg_ana` is driven directly by `DEBUG_ENABLE[3]` (bit 3), not
through any analog debug multiplexer.  The intent (routing VCO control voltage, phase
detector, or FIFO status to a single analog pad) requires the orphaned
`serdesphy_debug_mux.v` to be wired up.  In the current RTL, only a digital 0/1
reflecting `DEBUG_ENABLE[3]` reaches `dbg_ana`.

---

## Register Map (Authoritative Bit-Field → Signal Mapping)

| Addr | Reg | Bit | Signal | Reset |
|---|---|---|---|---|
| 0x00 | PHY_ENABLE | [0] | `phy_en` | 0 |
| 0x00 | PHY_ENABLE | [1] | `iso_en` | 1 |
| 0x01 | TX_CONFIG | [0] | `tx_en` | 0 |
| 0x01 | TX_CONFIG | [1] | `tx_fifo_en` | 0 |
| 0x01 | TX_CONFIG | [2] | `tx_prbs_en` | 0 |
| 0x01 | TX_CONFIG | [3] | `tx_idle` | 0 |
| 0x02 | RX_CONFIG | [0] | `rx_en` | 0 |
| 0x02 | RX_CONFIG | [1] | `rx_fifo_en` | 0 |
| 0x02 | RX_CONFIG | [2] | `rx_prbs_chk_en` | 0 |
| 0x02 | RX_CONFIG | [3] | `rx_align_rst` | 0 |
| 0x03 | DATA_SELECT | [0] | `tx_data_sel` | 0 |
| 0x03 | DATA_SELECT | [1] | `rx_data_sel` | 0 |
| 0x04 | PLL_CONFIG | [3:0] | `vco_trim[3:0]` | 0x8 |
| 0x04 | PLL_CONFIG | [5:4] | `cp_current[1:0]` | 0x2 |
| 0x04 | PLL_CONFIG | [6] | `pll_rst` | 1 |
| 0x04 | PLL_CONFIG | [7] | `pll_bypass` | 0 |
| 0x05 | CDR_CONFIG | [2:0] | `cdr_gain[2:0]` | 0x4 |
| 0x05 | CDR_CONFIG | [3] | `cdr_fast_lock` | 0 |
| 0x05 | CDR_CONFIG | [4] | `cdr_rst` | 1 |
| 0x06 | STATUS | [7:0] | (see above) | live |
| 0x07 | DEBUG_ENABLE | [0] | `dbg_vctrl` | 0 |
| 0x07 | DEBUG_ENABLE | [1] | `dbg_pd` | 0 |
| 0x07 | DEBUG_ENABLE | [2] | `dbg_fifo` | 0 |
| 0x07 | DEBUG_ENABLE | [3] | `dbg_ana` | 0 |

---

## Known Limitations

- `serdesphy_debug_mux.v` is orphaned; `dbg_ana` has no analog multiplexing.
- `reg_write_strobe` and `reg_write_addr` are routed to the module boundary but unused
  internally (no write-triggered side effects beyond what the register interface handles).
- Reserved bits are masked inside `serdesphy_registerInterface` (writes ignored, reads
  return 0); this is not visible at the `csr_top` level.
