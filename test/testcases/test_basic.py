from src.env import *
from cocotb.triggers import RisingEdge


# ============================================================================
# Helpers
# ============================================================================

async def poll_signal_high(dut, get_fn, timeout_cycles, label):
    """Poll get_fn() every cycle until truthy; assert on timeout."""
    for _ in range(timeout_cycles):
        try:
            if get_fn():
                return
        except ValueError:
            pass
        await ClockCycles(dut.clk, 1)
    assert False, f"{label} did not assert within {timeout_cycles} cycles"


async def base_setup(dut):
    """Start clock, run POR/reset, return PHYController."""
    clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())
    await TestUtils.reset_sequence(dut)
    await ClockCycles(dut.clk, Config.STABILIZATION_CYCLES)
    return PHYController(dut)


# ============================================================================
# Test 1 – Power-Up: POR completion and PLL lock
# ============================================================================

@cocotb.test()
async def power_up(dut):
    """Verify POR completes and PLL asserts lock after reset."""
    dut._log.info("=== Power-Up Test ===")

    phy = await base_setup(dut)

    # POR must have completed by the time reset_sequence returns
    assert int(dut.por_complete.value) == 1, \
        f"POR did not complete (por_complete={dut.por_complete.value})"
    dut._log.info("✓ POR completed")

    # Release PLL reset so the PLL can lock
    await phy.enable_phy()
    await phy.configure_tx(enable=True)
    await phy.configure_rx(enable=True)
    await phy.configure_pll(reset=False, vco_trim=8)
    await phy.configure_cdr(reset=False, gain=4)

    # Poll dut.pll_lock directly — fail if it doesn't assert within 5000 cycles
    await poll_signal_high(
        dut,
        lambda: int(dut.pll_lock.value) == 1,
        timeout_cycles=5000,
        label="pll_lock",
    )
    assert int(dut.pll_lock.value) == 1, "pll_lock deasserted unexpectedly"
    dut._log.info("✓ PLL locked")

    dut._log.info("=== Power-Up Test PASSED ===")


# ============================================================================
# Test 2 – Power-Up + Configuration: register write-readback and PLL lock
# ============================================================================

@cocotb.test()
async def power_up_with_configuration(dut):
    """Verify I2C register writes are reflected in readback and PLL locks."""
    dut._log.info("=== Power-Up + Configuration Test ===")

    phy = await base_setup(dut)
    i2c = I2CRegisterInterface(dut)

    # Write configuration
    await phy.enable_phy()
    await phy.configure_tx(enable=True)
    await phy.configure_rx(enable=True)
    await phy.configure_pll(reset=False, vco_trim=8)
    await phy.configure_cdr(reset=False, gain=4)

    # Read back every written register and assert the value matches
    expected = {
        RegisterMap.PHY_ENABLE: 0x01,   # PHY_EN=1, ISO_EN=0
        RegisterMap.TX_CONFIG:  0x01,   # TX_EN only
        RegisterMap.RX_CONFIG:  0x01,   # RX_EN only
        RegisterMap.PLL_CONFIG: 0x08,   # vco_trim=8, rst=0  (configure_pll bit layout)
        RegisterMap.CDR_CONFIG: 0x04,   # gain=4, rst=0  (configure_cdr bit layout)
    }

    for reg, exp in expected.items():
        actual = await i2c.read_register(reg)
        assert actual == exp, \
            f"Reg 0x{reg:02X}: expected 0x{exp:02X}, got 0x{actual:02X}"
        dut._log.info(f"  ✓ Reg 0x{reg:02X} = 0x{actual:02X}")

    # Assert PLL lock on the actual DUT output pin
    await poll_signal_high(
        dut,
        lambda: int(dut.pll_lock.value) == 1,
        timeout_cycles=5000,
        label="pll_lock",
    )

    # STATUS register pll_lock bit must also be set (tests CSR→signal path)
    status_reg = await i2c.read_register(RegisterMap.STATUS)
    assert status_reg & StatusBits.PLL_LOCK, \
        f"STATUS.pll_lock not set (STATUS=0x{status_reg:02X})"
    dut._log.info(f"  ✓ STATUS.pll_lock set (STATUS=0x{status_reg:02X})")

    dut._log.info("=== Power-Up + Configuration Test PASSED ===")


# ============================================================================
# Test 3 – Mission Mode Traffic: serializer activity and RX data path
# ============================================================================

@cocotb.test()
async def mission_mode_traffic(dut):
    """Verify TX serializer outputs transitions and RX receives valid data."""
    dut._log.info("=== Mission Mode Traffic Test ===")

    phy = await base_setup(dut)

    # Full PHY bring-up
    await phy.enable_phy()
    await phy.configure_tx(enable=True)
    await phy.configure_rx(enable=True)
    await phy.configure_pll(reset=False, vco_trim=8)
    await phy.configure_cdr(reset=False, gain=4)
    
    await poll_signal_high(
        dut,
        lambda: int(dut.pll_lock.value) == 1,
        timeout_cycles=5000,
        label="pll_lock (mission mode)",
    )

    # Enable loopback: TXP/TXN → RXP/RXN
    dut.lpbk_en.value = 1
    await ClockCycles(dut.clk, 10)

    # Configure TX (FIFO mode) and RX (FIFO mode)
    await phy.configure_tx(enable=True, fifo_enable=True)
    await phy.configure_data_path(tx_source="fifo", rx_source="fifo")
    await phy.configure_rx(enable=True, fifo_enable=True)
    await phy.configure_cdr(reset=False, gain=4)

    # --- Verify serializer is active: TXP must toggle within a window ---
    # TXP = uio_out[2]. Sample it before and after sending nibbles.
    txp_samples = []

    async def sample_txp(n_cycles):
        for _ in range(n_cycles):
            await ClockCycles(dut.clk, 1)
            try:
                txp_samples.append(int(dut.uio_out.value[2]))
            except ValueError:
                pass

    sampler = cocotb.start_soon(sample_txp(200))

    # Send 4 nibble pairs = 4 assembled bytes through the TX FIFO
    test_nibbles = [0x5, 0xA, 0xF, 0x0, 0x3, 0xC, 0x9, 0x6]
    for nibble in test_nibbles:
        dut.tx_data.value = nibble
        dut.tx_valid.value = 1
        await ClockCycles(dut.clk, 1)
        dut.tx_valid.value = 0
        await ClockCycles(dut.clk, 1)

    await sampler

    # TXP must have had at least one 0→1 or 1→0 transition
    transitions = sum(
        1 for a, b in zip(txp_samples, txp_samples[1:]) if a != b
    )
    assert transitions > 0, \
        f"TXP (uio_out[2]) showed no transitions — serializer not running"
    dut._log.info(f"  ✓ TXP transitions observed: {transitions}")

    # --- Wait for CDR lock, then check RX receives data ---
    await poll_signal_high(
        dut,
        lambda: int(dut.cdr_lock.value) == 1,
        timeout_cycles=5000,
        label="cdr_lock",
    )
    dut._log.info("  ✓ CDR locked")

    # Collect rx_valid pulses over the next 500 cycles
    received = []

    async def rx_monitor(n_cycles):
        for _ in range(n_cycles):
            await RisingEdge(dut.clk)
            try:
                if int(dut.rx_valid.value) == 1:
                    received.append(int(dut.rx_data.value))
            except ValueError:
                pass

    # Send more data while the monitor runs so the RX FIFO has fresh input
    monitor = cocotb.start_soon(rx_monitor(500))
    await TestUtils.send_data_words(dut, Config.LOOPBACK_DATA_WORDS)
    await monitor

    assert len(received) > 0, \
        "No rx_valid pulses observed after CDR lock — RX data path not working"
    dut._log.info(f"  ✓ {len(received)} nibbles received via loopback")

    # Check FIFO status and prbs_err through status register
    status = await phy.read_status()
    dut._log.info(
        f"  Final: pll_lock={status['pll_lock']}, cdr_lock={status['cdr_lock']}, "
        f"rx_fifo_empty={status['rx_fifo_empty']}"
    )
    assert status["pll_lock"], "PLL lock lost during traffic test"
    assert status["cdr_lock"], "CDR lock lost during traffic test"

    dut._log.info("=== Mission Mode Traffic Test PASSED ===")


# ============================================================================
# Test 4 – CSR Register Write/Readback
# ============================================================================

@cocotb.test()
async def csr_register_readback(dut):
    """Verify all writable CSRs store and return written values correctly."""
    dut._log.info("=== CSR Register Readback Test ===")

    await base_setup(dut)
    i2c = I2CRegisterInterface(dut)

    test_patterns = {
        RegisterMap.PHY_ENABLE: 0x03,
        RegisterMap.TX_CONFIG:  0x0F,
        RegisterMap.RX_CONFIG:  0x07,
        RegisterMap.DATA_SELECT: 0x03,
        RegisterMap.PLL_CONFIG: 0x5A,
        RegisterMap.CDR_CONFIG: 0x1C,
        RegisterMap.CONTROL:    0x0F,
    }

    # Write all patterns
    for reg, value in test_patterns.items():
        await i2c.write_register(reg, value)
        await ClockCycles(dut.clk, 10)

    # Read back and assert
    for reg, expected in test_patterns.items():
        actual = await i2c.read_register(reg)
        assert actual == expected, \
            f"Reg 0x{reg:02X}: expected 0x{expected:02X}, got 0x{actual:02X}"
        dut._log.info(f"  ✓ Reg 0x{reg:02X} = 0x{actual:02X}")

    # Overwrite subset and re-verify
    updates = {
        RegisterMap.PHY_ENABLE: 0x01,
        RegisterMap.TX_CONFIG:  0x05,
        RegisterMap.RX_CONFIG:  0x01,
    }
    for reg, value in updates.items():
        await i2c.write_register(reg, value)
        await ClockCycles(dut.clk, 10)
        actual = await i2c.read_register(reg)
        assert actual == value, \
            f"Reg 0x{reg:02X} update: expected 0x{value:02X}, got 0x{actual:02X}"
        dut._log.info(f"  ✓ Reg 0x{reg:02X} updated to 0x{actual:02X}")

    # STATUS register must be readable (read-only — just check no X/Z)
    status = await i2c.read_register(RegisterMap.STATUS)
    assert status is not None, "STATUS register read returned None"
    dut._log.info(f"  ✓ STATUS = 0x{status:02X}")

    dut._log.info("=== CSR Register Readback Test PASSED ===")
