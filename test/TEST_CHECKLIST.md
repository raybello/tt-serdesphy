# SerDes PHY Test Checklist

Comprehensive test coverage based on the system architecture (docs/info.md).

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
- [ ] **CLK_004**: PLL locks within 10 us
- [ ] **CLK_005**: PLL output is 240 MHz (10x reference)
- [ ] **CLK_006**: Verify PLL_LOCK assertion on lock
- [ ] **CLK_007**: Verify PLL_LOCK de-assertion on unlock
- [ ] **CLK_008**: Test VCO tuning range (200-400 MHz)
- [ ] **CLK_009**: Verify jitter < 100 ps RMS

---

## 5. Transmit Datapath

### 5.1 Word Assembler
- [ ] **TX_001**: Two 4-bit nibbles combine into 8-bit word
- [ ] **TX_002**: Word assembly timing (2 CLK_24M cycles)

### 5.2 TX FIFO
- [ ] **TX_003**: FIFO depth = 8 words
- [ ] **TX_004**: FIFO write with TX_VALID strobe
- [ ] **TX_005**: FIFO full flag at 7 words
- [ ] **TX_006**: FIFO empty flag at 0 words
- [ ] **TX_007**: Overflow asserts FIFO_ERR, discards data
- [ ] **TX_008**: Underflow behavior

### 5.3 PRBS Generator
- [ ] **TX_009**: PRBS-7 polynomial (x^7 + x^6 + 1)
- [ ] **TX_010**: 8-bit parallel output
- [ ] **TX_011**: Update rate = 24 MHz
- [ ] **TX_012**: PRBS bypasses FIFO when enabled

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
- [ ] **RX_003**: CDR locks within 100 us
- [ ] **RX_004**: Acquisition range +/- 2000 ppm
- [ ] **RX_005**: Tracking bandwidth ~1 MHz
- [ ] **RX_006**: Phase error < 0.1 UI for lock assertion
- [ ] **RX_007**: CDR_LOCK asserts after 64 consecutive good bits

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
- [ ] **RX_016**: Verify against expected PRBS-7 sequence
- [ ] **RX_017**: Single-bit error detection per 8-bit word
- [ ] **RX_018**: Error counter saturates at 255
- [ ] **RX_019**: Counter reset via RX_ALIGN_RST

---

## 7. Loopback Mode

- [ ] **LB_001**: Enable analog loopback via LPBK_EN pin
- [ ] **LB_002**: TX data appears at RX input
- [ ] **LB_003**: End-to-end data integrity with PRBS
- [ ] **LB_004**: End-to-end data integrity with FIFO data
- [ ] **LB_005**: CDR locks in loopback mode

---

## 8. Test Mode

- [ ] **TM_001**: TEST_MODE pin enables test features
- [ ] **TM_002**: Serializer bypass in test mode
- [ ] **TM_003**: Deserializer bypass in test mode

---

## 9. Initialization Sequence (Application)

Per datasheet Section 8.1:
- [ ] **INIT_001**: Apply AVDD, then DVDD
- [ ] **INIT_002**: Assert RST_N low for >= 10 CLK_REF cycles
- [ ] **INIT_003**: Write 0x01 to PHY_ENABLE
- [ ] **INIT_004**: Write 0x00 to PLL_CONFIG[6] (release PLL reset)
- [ ] **INIT_005**: Poll STATUS[0] until PLL_LOCK
- [ ] **INIT_006**: Write 0x05 to TX_CONFIG
- [ ] **INIT_007**: Write 0x00 to DATA_SELECT
- [ ] **INIT_008**: Write 0x00 to CDR_CONFIG[4] (release CDR reset)
- [ ] **INIT_009**: Write 0x05 to RX_CONFIG
- [ ] **INIT_010**: Poll STATUS[1] until CDR_LOCK
- [ ] **INIT_011**: Monitor STATUS[6] (PRBS_ERR stays low)

---

## 10. Error Conditions

- [ ] **ERR_001**: TX FIFO overflow handling
- [ ] **ERR_002**: TX FIFO underflow handling
- [ ] **ERR_003**: RX FIFO overflow handling
- [ ] **ERR_004**: RX FIFO underflow handling
- [ ] **ERR_005**: PLL unlock recovery
- [ ] **ERR_006**: CDR unlock recovery
- [ ] **ERR_007**: PRBS error detection and counting

---

## 11. Corner Cases

- [ ] **CC_001**: Power-on with supplies not OK
- [ ] **CC_002**: Reset during POR sequence
- [ ] **CC_003**: Rapid register writes
- [ ] **CC_004**: Back-to-back I2C transactions
- [ ] **CC_005**: Enable/disable transitions during operation
- [ ] **CC_006**: PLL/CDR reset during data transfer
- [ ] **CC_007**: Mode changes during operation

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
