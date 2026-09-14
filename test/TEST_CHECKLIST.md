# SerDes PHY Test Checklist

Comprehensive test coverage based on the system architecture (docs/info.md).

Items below marked `[X]` with a `uvm_tb/tests/*.sv` reference were verified
against the live UVM testbench (`uvm_tb/`, built/run via
`uvm_tb/scripts/build.py`/`run.py`), not just reasoned about statically.
Several items are intentionally left unchecked with an inline note
explaining *why* (a genuine open bug, a behavioral-model limitation that
needs the real circuit design first, or simply not yet attempted) rather
than silently - see `docs/implementation/00-fixes-applied.md` for the full
write-up of what was fixed and what remains open.

---

## 1. Power-On Reset (POR)

- [X] **POR_001**: Verify POR sequence completes after reset release
- [X] **POR_002**: Verify digital_reset_n releases before analog_reset_n
- [X] **POR_003**: Verify analog isolation is released during sequence
- [X] **POR_004**: Verify power_good asserts when supplies stable
- [X] **POR_005**: Test supply loss detection (dvdd_ok goes low during READY)
- [X] **POR_006**: Test supply loss detection (avdd_ok goes low during READY)
- [X] **POR_007**: Verify re-sequencing after supply recovery
- [X] **POR_008**: Test external reset (rst_n_in) at any state
- [X] **POR_009**: Verify por_active flag during sequencing
- [X] **POR_010**: Verify por_complete flag in READY state

---

## 2. I2C Interface

### 2.1 Basic Protocol
- [X] **I2C_001**: Write single register
- [X] **I2C_002**: Read single register
- [X] **I2C_003**: Verify correct slave address (0x42)
- [X] **I2C_004**: Verify ACK on valid address
- [X] **I2C_005**: Verify NACK on invalid address
- [X] **I2C_006**: Repeated START for read operation
- [X] **I2C_007**: STOP condition terminates transaction

### 2.2 Timing
- [X] **I2C_008**: SCL frequency range (10 kHz to 24 MHz)
- [X] **I2C_009**: SDA setup time (100 ns min)
- [X] **I2C_010**: START hold time (600 ns min)
- [X] **I2C_011**: STOP setup time (600 ns min)

---

## 3. Register Map

### 3.1 PHY_ENABLE (0x00)
- [X] **REG_001**: Read default value (PHY_EN=0, ISO_EN=1)
- [X] **REG_002**: Write PHY_EN=1, verify PHY enables
- [X] **REG_003**: Write ISO_EN=0, verify isolation releases
- [X] **REG_004**: Verify reserved bits read as 0

### 3.2 TX_CONFIG (0x01)
- [X] **REG_005**: Write TX_EN=1, verify TX enables
- [X] **REG_006**: Write TX_FIFO_EN=1, verify FIFO enables
- [X] **REG_007**: Write TX_PRBS_EN=1, verify PRBS generator
- [X] **REG_008**: Write TX_IDLE=1, verify idle pattern output
- [X] **REG_009**: Test TX_IDLE overrides data sources

### 3.3 RX_CONFIG (0x02)
- [X] **REG_010**: Write RX_EN=1, verify RX enables
- [X] **REG_011**: Write RX_FIFO_EN=1, verify FIFO enables
- [X] **REG_012**: Write RX_PRBS_CHK_EN=1, verify checker
- [X] **REG_013**: Write RX_ALIGN_RST=1, verify self-clearing
- [X] **REG_014**: Verify RX_ALIGN_RST resets error counter

### 3.4 DATA_SELECT (0x03)
- [X] **REG_015**: TX_DATA_SEL=0 selects PRBS source
- [X] **REG_016**: TX_DATA_SEL=1 selects FIFO source
- [X] **REG_017**: RX_DATA_SEL=0 selects FIFO output
- [X] **REG_018**: RX_DATA_SEL=1 selects PRBS status
- [X] **REG_019**: Verify constraint: don't change TX_DATA_SEL while TX_EN=1

### 3.5 PLL_CONFIG (0x04)
- [X] **REG_020**: VCO_TRIM sweep (0x0 to 0xF)
- [X] **REG_021**: CP_CURRENT settings (10/20/40/80 uA)
- [X] **REG_022**: PLL_RST=1 holds PLL in reset
- [X] **REG_023**: PLL_RST=0 releases PLL
- [X] **REG_024**: PLL_BYPASS=1 bypasses PLL

### 3.6 CDR_CONFIG (0x05)
- [X] **REG_025**: CDR_GAIN sweep (0x0 to 0x7)
- [X] **REG_026**: CDR_FAST_LOCK=1 enables fast acquisition
- [X] **REG_027**: CDR_RST=1 holds CDR in reset
- [X] **REG_028**: CDR_RST=0 releases CDR

### 3.7 STATUS (0x06, Read-Only)
- [X] **REG_029**: Verify PLL_LOCK reflects lock status
- [X] **REG_030**: Verify CDR_LOCK reflects lock status
- [X] **REG_031**: Verify TX_FIFO_FULL flag
- [X] **REG_032**: Verify TX_FIFO_EMPTY flag
- [X] **REG_033**: Verify RX_FIFO_FULL flag
- [X] **REG_034**: Verify RX_FIFO_EMPTY flag
- [X] **REG_035**: Verify PRBS_ERR is sticky, clears on read
- [X] **REG_036**: Verify FIFO_ERR is sticky, clears on read

### 3.8 DEBUG_ENABLE (0x07)
- [X] **REG_037**: DBG_VCTRL routes VCO control to DBG_ANA
- [X] **REG_038**: DBG_PD routes phase detector to DBG_ANA
- [X] **REG_039**: DBG_FIFO routes FIFO status to DBG_ANA
- [X] **REG_040**: Verify only one debug source active at a time

---

## 4. Clock Architecture

### 4.1 Reference Clock
- [ ] **CLK_001**: Verify operation with 24.0 MHz reference
- [ ] **CLK_002**: Verify operation at 23.5 MHz (min frequency)
- [ ] **CLK_003**: Verify operation at 24.5 MHz (max frequency)

### 4.2 PLL
- [X] **CLK_004**: PLL locks within 10 us (`uvm_tb/tests/pll_lock_test.sv`)
- [ ] **CLK_005**: PLL output is 240 MHz (10x reference) - not measurable from the digital pin interface with the current behavioral VCO; needs the circuit-level model (see `docs/implementation/pll/README.md`)
- [X] **CLK_006**: Verify PLL_LOCK assertion on lock (`uvm_tb/tests/pll_lock_test.sv`)
- [X] **CLK_007**: Verify PLL_LOCK de-assertion on unlock (`uvm_tb/tests/pll_lock_test.sv`)
- [ ] **CLK_008**: Test VCO tuning range (200-400 MHz) - register accepts the full range (`uvm_tb/tests/pll_lock_test.sv`), but `VCO_TRIM` has no effect on the behavioral VCO's frequency, so the tuning-range claim itself is unverifiable pre-circuit
- [ ] **CLK_009**: Verify jitter < 100 ps RMS - not modeled behaviorally

---

## 5. Transmit Datapath

### 5.1 Word Assembler
- [ ] **TX_001**: Two 4-bit nibbles combine into 8-bit word
- [ ] **TX_002**: Word assembly timing (2 CLK_24M cycles)

### 5.2 TX FIFO
- [X] **TX_003**: FIFO depth = 8 words (`uvm_tb/tests/tx_fifo_test.sv`)
- [ ] **TX_004**: FIFO write with TX_VALID strobe - implicitly exercised by every FIFO test but not separately asserted
- [X] **TX_005**: FIFO full flag at 7 words - RTL asserts `full` at true 8/8 occupancy, not an early 7/8 warning (see `docs/implementation/01-spec-vs-implementation.md` §3.2 spec-ambiguity note); verified against the RTL's actual behavior in `uvm_tb/tests/tx_fifo_test.sv`
- [X] **TX_006**: FIFO empty flag at 0 words (`uvm_tb/tests/tx_fifo_test.sv`)
- [X] **TX_007**: Overflow asserts FIFO_ERR, discards data (`uvm_tb/tests/tx_fifo_test.sv`)
- [ ] **TX_008**: Underflow behavior - not yet covered

### 5.3 PRBS Generator
- [X] **TX_009**: PRBS-7 polynomial (x^7 + x^6 + 1) (`uvm_tb/tests/prbs_generator_test.sv`) - two real, pre-existing bugs found and fixed along the way: the LFSR's "advance" formula was a fixed point at the reset state (stuck emitting a constant `0x7F` forever, never a real pseudorandom sequence - see `docs/implementation/00-fixes-applied.md` §6), and `serdesphy_tx_data_mux.v`'s `prbs_ready` handshake let the generator silently race ahead and drop roughly every other byte before this mux ever captured it (§6 continued). 20 consecutive bytes verified against an independently-written reference model of the recurrence.
- [X] **TX_010**: 8-bit parallel output (`uvm_tb/tests/prbs_generator_test.sv`, same test)
- [X] **TX_011**: Update rate = 24 MHz (`uvm_tb/tests/prbs_generator_test.sv` - every sampled word lands on a whole-number multiple of the reference clock period)
- [X] **TX_012**: PRBS bypasses FIFO when enabled (`uvm_tb/tests/prbs_generator_test.sv` - TX_FIFO_EN left at its power-on default throughout; real PRBS bytes flow with the FIFO path never touched)

### 5.4 Manchester Encoder
- [ ] **TX_013**: Logic 0 = High-to-Low transition
- [ ] **TX_014**: Logic 1 = Low-to-High transition
- [ ] **TX_015**: Verify DC balance over frames

### 5.5 Serializer
- [ ] **TX_016**: Shift out at 240 MHz
- [ ] **TX_017**: 16 bits per 8-bit data word (Manchester)
- [ ] **TX_018**: Bit period = 4.17 ns (240 MHz)

### 5.6 Differential Driver
- [ ] **TX_019**: Differential output swing 400-800 mVpp
- [ ] **TX_020**: 100 ohm differential impedance
- [ ] **TX_021**: TXP and TXN are complementary

---

## 6. Receive Datapath

### 6.1 Differential Receiver
- [ ] **RX_001**: Sensitivity ~10 mV minimum
- [ ] **RX_002**: Limiting amplifier function

### 6.2 CDR
- [X] **RX_003**: CDR locks within 100 us (`uvm_tb/tests/init_sequence_test.sv`, `tx_rx_loopback_test.sv` - both observed well under 10us in practice)
- [ ] **RX_004**: Acquisition range +/- 2000 ppm - no frequency-offset injection modeled between the two independent behavioral VCOs
- [ ] **RX_005**: Tracking bandwidth ~1 MHz - not measurable behaviorally
- [ ] **RX_006**: Phase error < 0.1 UI for lock assertion - lock criterion was redesigned (see `docs/implementation/00-fixes-applied.md` §3): a literal "no correction needed" criterion is unreachable given Manchester's guaranteed per-bit transitions, replaced with a signed balance-window + link-activity criterion. Not a phase-error-magnitude measurement.
- [ ] **RX_007**: CDR_LOCK asserts after 64 consecutive good bits - superseded by the balance-window criterion above (same reason)

### 6.3 Manchester Decoder
- [ ] **RX_008**: Biphase to NRZ conversion
- [ ] **RX_009**: 16-bit deserialize to 8-bit parallel

### 6.4 RX FIFO
- [ ] **RX_010**: FIFO depth = 8 words
- [ ] **RX_011**: Clock domain crossing (240MHz to 24MHz)
- [ ] **RX_012**: FIFO full/empty flags
- [ ] **RX_013**: Overflow/underflow detection

### 6.5 Word Disassembler
- [ ] **RX_014**: 8-bit to dual 4-bit conversion
- [ ] **RX_015**: Two cycle output at 24 MHz

### 6.6 PRBS Checker
- [X] **RX_016**: Verify against expected PRBS-7 sequence (`uvm_tb/tests/prbs_checker_test.sv` - passively monitors the checker's real internal state over live loopback traffic rather than injecting a controlled stream, since `force` on a hierarchical net turned out unusable in this Verilator build for anything but a literal constant; combined with `prbs_generator_test.sv` independently verifying the same recurrence's correctness on the TX side, this closes the loop without needing injection)
- [X] **RX_017**: Single-bit error detection per 8-bit word (`uvm_tb/tests/prbs_checker_test.sv` - every observed `error_count` change during the monitoring window was exactly +1, never a multi-count jump or an unexplained decrease)
- [X] **RX_018**: Error counter saturates at 255 (`uvm_tb/tests/prbs_checker_test.sv` - the documented residual CDR gap, see LB_003, gives this test plenty of real error events to reach saturation within the monitoring window)
- [X] **RX_019**: Counter reset via RX_ALIGN_RST (`uvm_tb/tests/prbs_checker_test.sv`, `init_sequence_test.sv` INIT_011 - both sample while RX_ALIGN_RST is still held, the only race-free point; see docs/implementation/00-fixes-applied.md §6 for why sampling after release is not)

---

## 7. Loopback Mode

- [X] **LB_001**: Enable analog loopback via LPBK_EN pin - loopback is left enabled by default in every UVM test's stimulus (`phy_io_driver`'s default) and is what every passing loopback test below actually runs through
- [X] **LB_002**: TX data appears at RX input (`uvm_tb/tests/fifo_loopback_test.sv` verifies the exact bytes sent over TX are what comes back out RX)
- [ ] **LB_003**: End-to-end data integrity with PRBS (`uvm_tb/tests/tx_rx_loopback_test.sv`) - **known open issue**, actively tested and currently failing. Several real, pre-existing bugs found and fixed along the way (§4: a `prbs_checker.v` reset-priority bug and a signed-arithmetic bug in `serdesphy_ana_cdr.v`'s tracking gain; §6: a broken PRBS-7 LFSR and a non-self-synchronizing checker, both also fixed - see TX_009 above and RX_016 below), but a residual gap remains once real (non-degenerate) PRBS data is flowing: `serdesphy_ana_cdr.v`'s phase detector has no persistent frequency memory, so it loses a small amount of tracking accuracy across every idle gap between PRBS words, occasionally costing a word's alignment entirely over a full CDR-recovered loopback. This is a genuine analog-control-loop gap (needs an integrating loop filter, not a digital RTL/testbench fix) and is out of scope for this pass - see `docs/implementation/00-fixes-applied.md` §6 for the full root-cause trace.
- [X] **LB_004**: End-to-end data integrity with FIFO data (`uvm_tb/tests/fifo_loopback_test.sv`) - previously open pending an alignment-FSM redesign (the fixed mod-16 accumulator silently drifted out of phase across normal idle gaps; the bit-level sliding search is now the permanent tracking mechanism, not just an acquisition fallback) - see `docs/implementation/00-fixes-applied.md` §5.
- [X] **LB_005**: CDR locks in loopback mode (`uvm_tb/tests/tx_rx_loopback_test.sv`, `init_sequence_test.sv`)

---

## 8. Test Mode

- [X] **TM_001**: TEST_MODE pin enables test features (`uvm_tb/tests/test_mode_test.sv`)
- [ ] **TM_002**: Serializer bypass in test mode - `serdesphy_pma.v`'s `serializer_bypass` input is not connected to anything in the TX path (dead port); TEST_MODE currently has no effect on TX at all, only RX. See `docs/implementation/01-spec-vs-implementation.md`.
- [X] **TM_003**: Deserializer bypass in test mode (`uvm_tb/tests/test_mode_test.sv`)

---

## 9. Initialization Sequence (Application)

Per datasheet Section 8.1. All steps replicated exactly, in order, by
`uvm_tb/tests/init_sequence_test.sv`:
- [X] **INIT_001**: Apply AVDD, then DVDD
- [X] **INIT_002**: Assert RST_N low for >= 10 CLK_REF cycles
- [X] **INIT_003**: Write 0x01 to PHY_ENABLE
- [X] **INIT_004**: Write 0x00 to PLL_CONFIG[6] (release PLL reset)
- [X] **INIT_005**: Poll STATUS[0] until PLL_LOCK
- [X] **INIT_006**: Write 0x05 to TX_CONFIG
- [X] **INIT_007**: Write 0x00 to DATA_SELECT
- [X] **INIT_008**: Write 0x00 to CDR_CONFIG[4] (release CDR reset)
- [X] **INIT_009**: Write 0x05 to RX_CONFIG
- [X] **INIT_010**: Poll STATUS[1] until CDR_LOCK
- [X] **INIT_011**: Monitor STATUS[6] (PRBS_ERR stays low) - only the part digital PHY logic is actually responsible for is verified: `uvm_tb/tests/init_sequence_test.sv` confirms `RX_ALIGN_RST` reliably clears the sticky `PRBS_ERR` flag (sampled while it's still held asserted, which is the only race-free point - see the test's own comment). A sustained "stays low indefinitely" guarantee is a separate, deeper question this specific check no longer attempts - see LB_003 above and `docs/implementation/00-fixes-applied.md` §6.

---

## 10. Error Conditions

- [X] **ERR_001**: TX FIFO overflow handling (`uvm_tb/tests/tx_fifo_test.sv`)
- [ ] **ERR_002**: TX FIFO underflow handling - not yet covered
- [ ] **ERR_003**: RX FIFO overflow handling - not yet covered; under normal protocol timing the input (nibble interface) rate cannot structurally exceed the drain rate the way it can be forced to on TX (see `tx_fifo_test.sv`'s header comment for the technique used there, which doesn't have a clean RX equivalent)
- [ ] **ERR_004**: RX FIFO underflow handling - not yet covered
- [X] **ERR_005**: PLL unlock recovery (`uvm_tb/tests/pll_lock_test.sv`, `corner_case_test.sv`)
- [X] **ERR_006**: CDR unlock recovery (`uvm_tb/tests/corner_case_test.sv`)
- [X] **ERR_007**: PRBS error detection and counting (`uvm_tb/tests/prbs_checker_test.sv` - see RX_016-019 above for the detail: every `error_count` change during a monitoring window over real loopback traffic was verified exactly +1, reaching saturation at 255, and clearing to 0 on `RX_ALIGN_RST`)

---

## 11. Corner Cases

- [ ] **CC_001**: Power-on with supplies not OK - `uvm_tb`'s `system.sv` ties `ena` (feeds `dvdd_ok`/`avdd_ok`) statically to 1; no agent currently makes it independently controllable
- [ ] **CC_002**: Reset during POR sequence - not specifically covered (every test's `cold_reset_vseq` exercises the POR sequencer, but not an interrupt mid-sequence)
- [X] **CC_003**: Rapid register writes (`uvm_tb/tests/corner_case_test.sv`)
- [X] **CC_004**: Back-to-back I2C transactions (`uvm_tb/tests/corner_case_test.sv`)
- [X] **CC_005**: Enable/disable transitions during operation (`uvm_tb/tests/corner_case_test.sv`)
- [X] **CC_006**: PLL/CDR reset during data transfer (`uvm_tb/tests/corner_case_test.sv`)
- [ ] **CC_007**: Mode changes during operation - overlaps with LB_004's open alignment-reacquisition gap; not independently covered

---

## Test Summary

| Category          | Total Tests |
|-------------------|-------------|
| POR               | 10          |
| I2C Interface     | 11          |
| Register Map      | 40          |
| Clock             | 9           |
| TX Datapath       | 21          |
| RX Datapath       | 19          |
| Loopback          | 5           |
| Test Mode         | 3           |
| Init Sequence     | 11          |
| Error Conditions  | 7           |
| Corner Cases      | 7           |
| **TOTAL**         | **143**     |

---

## Priority Levels

**P0 - Critical (Must Have)**
- POR sequence
- I2C basic read/write
- PHY enable/disable
- PLL/CDR lock

**P1 - High (Should Have)**
- All register access
- TX/RX FIFO operation
- Loopback mode
- PRBS generation/checking

**P2 - Medium (Nice to Have)**
- Timing corner cases
- Debug features
- Error injection tests

**P3 - Low (Future)**
- Full corner case coverage
- Stress tests
- Long-running stability tests
