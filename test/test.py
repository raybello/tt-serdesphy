from src.env import *

from testcases.test_i2c import *
from testcases.test_por import *
from testcases.test_registers import *

# ============================================================================
# Test Cases
# ============================================================================

@cocotb.test()
async def power_up(dut):
    """Test 1: Basic Power-Up Test"""
    dut._log.info("=== Power-Up Test Started ===")
    
    clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())
    
    await TestUtils.reset_sequence(dut)
    
    dut._log.info("Waiting for stabilization")
    await ClockCycles(dut.clk, Config.STABILIZATION_CYCLES)
    
    # Read default register values
    dut._log.info("Reading default register values")
    i2c = I2CRegisterInterface(dut)
    values = await i2c.read_all_registers()
    
    for addr, value in values.items():
        dut._log.info(f"  Reg 0x{addr:02X} = 0x{value:02X}")
    
    # Check for lock
    phy = PHYController(dut)
    await phy.wait_for_lock(timeout_ns=1000000)
    
    dut._log.info("=== Power-Up Test Completed ===")


@cocotb.test()
async def power_up_with_configuration(dut):
    """Test 2: Power-Up + I2C Configuration Test"""
    dut._log.info("=== Power-Up + Configuration Test Started ===")
    
    clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())
    
    await TestUtils.reset_sequence(dut)
    await ClockCycles(dut.clk, Config.STABILIZATION_CYCLES)
    
    # Configure PHY
    dut._log.info("Configuring PHY")
    phy = PHYController(dut)
    
    await phy.enable_phy()
    await phy.configure_tx(enable=True)
    await phy.configure_rx(enable=True)
    await phy.configure_pll(reset=False, vco_trim=8)
    await phy.configure_cdr(reset=False, gain=4)
    
    # Verify configuration
    dut._log.info("Verifying configuration")
    i2c = I2CRegisterInterface(dut)
    values = await i2c.read_all_registers()
    
    dut._log.info(f"  PHY Enable: 0x{values[RegisterMap.PHY_ENABLE]:02X}")
    dut._log.info(f"  TX Config: 0x{values[RegisterMap.TX_CONFIG]:02X}")
    dut._log.info(f"  RX Config: 0x{values[RegisterMap.RX_CONFIG]:02X}")
    dut._log.info(f"  PLL Config: 0x{values[RegisterMap.PLL_CONFIG]:02X}")
    dut._log.info(f"  CDR Config: 0x{values[RegisterMap.CDR_CONFIG]:02X}")
    
    # Wait for lock
    await phy.wait_for_lock(timeout_ns=1000000)
    
    dut._log.info("=== Power-Up + Configuration Test Completed ===")


@cocotb.test()
async def mission_mode_traffic(dut):
    """Test 3: Mission Mode Traffic Test"""
    dut._log.info("=== Mission Mode Traffic Test Started ===")
    
    clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())
    
    await TestUtils.reset_sequence(dut)
    await ClockCycles(dut.clk, Config.STABILIZATION_CYCLES)
    
    # Configure for mission mode
    dut._log.info("Configuring for mission mode")
    phy = PHYController(dut)
    
    await phy.enable_phy()
    await phy.configure_tx(enable=True, fifo_enable=True)
    await phy.configure_rx(enable=True, fifo_enable=True)
    await phy.configure_data_path(tx_source='fifo', rx_source='fifo')
    await phy.configure_pll(reset=False, vco_trim=8)
    await phy.configure_cdr(reset=False, gain=4)
    
    # Wait for lock
    dut._log.info("Waiting for PLL/CDR lock")
    locked = await phy.wait_for_lock(timeout_ns=2000000)
    
    # Send test traffic
    dut._log.info(f"Sending {Config.MISSION_MODE_DATA_WORDS} data words")
    await TestUtils.send_data_words(dut, Config.MISSION_MODE_DATA_WORDS)
    
    # Check FIFO status
    status = await phy.read_status()
    dut._log.info(f"FIFO Status: TX Full={status['tx_fifo_full']}, "
                  f"TX Empty={status['tx_fifo_empty']}, "
                  f"RX Full={status['rx_fifo_full']}, "
                  f"RX Empty={status['rx_fifo_empty']}")
    
    # Enable loopback
    dut._log.info("Enabling loopback for end-to-end test")
    dut.lpbk_en.value = 1
    await ClockCycles(dut.clk, 10)
    
    # Send loopback data
    dut._log.info(f"Sending {Config.LOOPBACK_DATA_WORDS} loopback words")
    await TestUtils.send_data_words(dut, Config.LOOPBACK_DATA_WORDS)
    
    # Check RX data
    await ClockCycles(dut.clk, 5)
    rx_data, rx_valid = TestUtils.safe_read_rx_data(dut)
    dut._log.info(f"RX Data: 0x{rx_data:01X} (valid={rx_valid})")
    
    # Final status
    final_status = await phy.read_status()
    if final_status['pll_lock'] and final_status['cdr_lock']:
        dut._log.info("✓ Mission mode test PASSED")
    else:
        dut._log.warning("✗ Mission mode test FAILED")
    
    dut._log.info("=== Mission Mode Traffic Test Completed ===")


@cocotb.test()
async def csr_register_readback(dut):
    """Test 4: CSR Register Write and Readback Test

    This test verifies that CSR values written via I2C are properly
    stored in registers and can be read back correctly.
    """
    dut._log.info("=== CSR Register Readback Test Started ===")

    clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await TestUtils.reset_sequence(dut)
    await ClockCycles(dut.clk, Config.STABILIZATION_CYCLES)

    i2c = I2CRegisterInterface(dut)

    # Test data patterns for each register
    test_patterns = {
        RegisterMap.PHY_ENABLE:  0x03,   # Enable PHY and isolation
        RegisterMap.TX_CONFIG:   0x0F,   # Enable all TX features
        RegisterMap.RX_CONFIG:   0x07,   # Enable RX, FIFO, PRBS check
        RegisterMap.DATA_SELECT: 0x03,   # Both TX and RX select high
        RegisterMap.PLL_CONFIG:  0x5A,   # VCO=10, CP=1, PLL_RST=0, BYPASS=0
        RegisterMap.CDR_CONFIG:  0x1C,   # Gain=4, fast_lock=1, reset=1
        RegisterMap.CONTROL:     0x0F,   # Debug enables
    }

    # Write test patterns to all writable registers
    dut._log.info("Writing test patterns to registers...")
    for reg_addr, value in test_patterns.items():
        dut._log.info(f"  Writing 0x{value:02X} to reg 0x{reg_addr:02X}")
        await i2c.write_register(reg_addr, value)
        await ClockCycles(dut.clk, 10)  # Small delay between writes

    # Read back and verify all registers
    dut._log.info("Reading back and verifying registers...")
    all_passed = True

    for reg_addr, expected in test_patterns.items():
        actual = await i2c.read_register(reg_addr)

        if actual == expected:
            dut._log.info(f"  Reg 0x{reg_addr:02X}: PASS (0x{actual:02X})")
        else:
            dut._log.error(f"  Reg 0x{reg_addr:02X}: FAIL (expected 0x{expected:02X}, got 0x{actual:02X})")
            all_passed = False

    # Also read the status register (read-only)
    status = await i2c.read_register(RegisterMap.STATUS)
    dut._log.info(f"  Status Reg 0x{RegisterMap.STATUS:02X}: 0x{status:02X}")

    # Test write-then-read with different values
    dut._log.info("Testing register update with new values...")

    new_patterns = {
        RegisterMap.PHY_ENABLE:  0x01,   # Only PHY enable
        RegisterMap.TX_CONFIG:   0x05,   # TX enable + PRBS
        RegisterMap.RX_CONFIG:   0x01,   # Only RX enable
    }

    for reg_addr, value in new_patterns.items():
        await i2c.write_register(reg_addr, value)
        await ClockCycles(dut.clk, 10)
        actual = await i2c.read_register(reg_addr)

        if actual == value:
            dut._log.info(f"  Reg 0x{reg_addr:02X}: PASS (updated to 0x{actual:02X})")
        else:
            dut._log.error(f"  Reg 0x{reg_addr:02X}: FAIL (expected 0x{value:02X}, got 0x{actual:02X})")
            all_passed = False

    # Final summary
    if all_passed:
        dut._log.info("✓ CSR Register Readback Test PASSED")
    else:
        dut._log.error("✗ CSR Register Readback Test FAILED")
        assert False, "Register readback verification failed"

    dut._log.info("=== CSR Register Readback Test Completed ===")
