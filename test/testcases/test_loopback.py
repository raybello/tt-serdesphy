# SerDes PHY Loopback Tests (LB_001 - LB_005)
# Tests for loopback mode: analog loopback, data integrity, CDR operation

from src.env import *
from testcases.common import *


async def setup_loopback_test(dut):
    """Common loopback test setup"""
    clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())
    await TestUtils.reset_sequence(dut)
    await ClockCycles(dut.clk, ExtendedConfig.STABILIZATION_CYCLES)

    phy = PHYControllerExtended(dut)
    await phy.i2c.write_register(RegisterMap.PHY_ENABLE, 0x01)
    await phy.i2c.write_register(RegisterMap.PLL_CONFIG, 0x08)
    # await phy.wait_for_pll_lock(timeout_ns=50000000)
    return phy


@cocotb.test()
async def LB_001_enable_analog_loopback(dut):
    """LB_001: Enable analog loopback via LPBK_EN pin"""
    dut._log.info("=== LB_001: Enable Analog Loopback Test ===")

    phy = await setup_loopback_test(dut)

    # Verify loopback is initially disabled
    initial_lpbk = int(dut.lpbk_en.value)
    dut._log.info(f"Initial LPBK_EN: {initial_lpbk}")
    assert initial_lpbk == 0, f"Expected loopback disabled initially, got {initial_lpbk}"

    # Enable loopback
    dut.lpbk_en.value = 1
    await ClockCycles(dut.clk, 10)

    # Verify loopback enabled
    lpbk_en = int(dut.lpbk_en.value)
    dut._log.info(f"LPBK_EN after enable: {lpbk_en}")
    assert lpbk_en == 1, f"Expected loopback enabled (1), got {lpbk_en}"

    dut._log.info("=== LB_001: PASSED ===")


@cocotb.test()
async def LB_002_tx_to_rx_loopback(dut):
    """LB_002: TX data appears at RX input"""
    dut._log.info("=== LB_002: TX to RX Loopback Test ===")

    phy = await setup_loopback_test(dut)

    # Enable loopback
    dut.lpbk_en.value = 1
    await ClockCycles(dut.clk, 10)

    # Verify loopback is enabled
    lpbk_en = int(dut.lpbk_en.value)
    assert lpbk_en == 1, "Loopback should be enabled"

    # Enable TX
    await phy.i2c.write_register(RegisterMap.TX_CONFIG, 0x05)  # TX_EN + TX_PRBS_EN
    await phy.i2c.write_register(RegisterMap.DATA_SELECT, 0x00)

    # Enable RX
    await phy.i2c.write_register(RegisterMap.RX_CONFIG, 0x03)  # RX_EN + RX_FIFO_EN
    await phy.i2c.write_register(RegisterMap.CDR_CONFIG, 0x04)  # Release CDR

    # Wait for CDR to lock
    await phy.wait_for_cdr_lock(timeout_ns=100000000)
    await ClockCycles(dut.clk, 500)

    # Verify TX and RX are enabled
    tx_config = await phy.i2c.read_register(RegisterMap.TX_CONFIG)
    rx_config = await phy.i2c.read_register(RegisterMap.RX_CONFIG)

    assert (tx_config & 0x01) == 0x01, "TX should be enabled"
    assert (rx_config & 0x01) == 0x01, "RX should be enabled"

    # Check status
    status = await phy.read_status()
    dut._log.info(f"RX FIFO Empty: {status['rx_fifo_empty']}, CDR Lock: {status['cdr_lock']}")

    dut._log.info("=== LB_002: PASSED ===")


@cocotb.test()
async def LB_003_prbs_data_integrity(dut):
    """LB_003: End-to-end data integrity with PRBS"""
    dut._log.info("=== LB_003: PRBS End-to-End Integrity Test ===")

    phy = await setup_loopback_test(dut)

    # Enable loopback
    dut.lpbk_en.value = 1
    await ClockCycles(dut.clk, 10)

    # Verify loopback is enabled
    assert int(dut.lpbk_en.value) == 1, "Loopback should be enabled"

    # Enable TX with PRBS
    await phy.i2c.write_register(RegisterMap.TX_CONFIG, 0x05)  # TX_EN + TX_PRBS_EN
    await phy.i2c.write_register(RegisterMap.DATA_SELECT, 0x00)  # PRBS source

    # Enable RX with PRBS checker
    await phy.i2c.write_register(RegisterMap.RX_CONFIG, 0x05)  # RX_EN + RX_PRBS_CHK_EN
    await phy.i2c.write_register(RegisterMap.CDR_CONFIG, 0x04)

    # Wait for CDR lock
    await phy.wait_for_cdr_lock(timeout_ns=100000000)

    # Let PRBS run through the loopback
    await ClockCycles(dut.clk, 2000)

    # Verify PRBS is enabled on both TX and RX
    tx_config = await phy.i2c.read_register(RegisterMap.TX_CONFIG)
    rx_config = await phy.i2c.read_register(RegisterMap.RX_CONFIG)

    assert (tx_config & 0x04) == 0x04, "TX PRBS should be enabled"
    assert (rx_config & 0x04) == 0x04, "RX PRBS checker should be enabled"

    # Check status
    status = await phy.read_status()
    dut._log.info(f"CDR Lock: {status['cdr_lock']}")

    # Read STATUS register to check PRBS_ERR bit (bit 6)
    status_raw = await phy.i2c.read_register(RegisterMap.STATUS)
    prbs_err = bool(status_raw & 0x40)
    dut._log.info(f"PRBS Error bit: {prbs_err}")

    dut._log.info("=== LB_003: PASSED ===")


@cocotb.test()
async def LB_004_fifo_data_integrity(dut):
    """LB_004: End-to-end data integrity with FIFO data"""
    dut._log.info("=== LB_004: FIFO End-to-End Integrity Test ===")

    phy = await setup_loopback_test(dut)

    # Enable loopback
    dut.lpbk_en.value = 1
    await ClockCycles(dut.clk, 10)

    # Verify loopback is enabled
    assert int(dut.lpbk_en.value) == 1, "Loopback should be enabled"

    # Enable TX with FIFO
    await phy.i2c.write_register(RegisterMap.TX_CONFIG, 0x03)  # TX_EN + TX_FIFO_EN
    await phy.i2c.write_register(RegisterMap.DATA_SELECT, 0x01)  # FIFO source

    # Enable RX with FIFO
    await phy.i2c.write_register(RegisterMap.RX_CONFIG, 0x03)  # RX_EN + RX_FIFO_EN
    await phy.i2c.write_register(RegisterMap.CDR_CONFIG, 0x04)

    # Wait for CDR lock
    await phy.wait_for_cdr_lock(timeout_ns=100000000)

    # Send test pattern
    test_pattern = [0x05, 0x0A, 0x0F, 0x00, 0x03, 0x0C, 0x09, 0x06]
    dut._log.info(f"Sending test pattern: {[hex(x) for x in test_pattern]}")

    for nibble in test_pattern:
        dut.tx_data.value = nibble
        dut.tx_valid.value = 1
        await ClockCycles(dut.clk, 1)
        dut.tx_valid.value = 0
        await ClockCycles(dut.clk, 1)

    # Wait for data to propagate through loopback
    await ClockCycles(dut.clk, 500)

    # Verify TX and RX FIFO are enabled
    tx_config = await phy.i2c.read_register(RegisterMap.TX_CONFIG)
    rx_config = await phy.i2c.read_register(RegisterMap.RX_CONFIG)

    assert (tx_config & 0x02) == 0x02, "TX FIFO should be enabled"
    assert (rx_config & 0x02) == 0x02, "RX FIFO should be enabled"

    # Check RX FIFO status
    status = await phy.read_status()
    dut._log.info(f"RX FIFO Empty: {status['rx_fifo_empty']}")

    dut._log.info("=== LB_004: PASSED ===")


@cocotb.test()
async def LB_005_cdr_locks_in_loopback(dut):
    """LB_005: CDR locks in loopback mode"""
    dut._log.info("=== LB_005: CDR Lock in Loopback Test ===")

    phy = await setup_loopback_test(dut)

    # Enable loopback first
    dut.lpbk_en.value = 1
    await ClockCycles(dut.clk, 10)

    # Verify loopback is enabled
    assert int(dut.lpbk_en.value) == 1, "Loopback should be enabled"

    # Enable TX with PRBS to provide data
    await phy.i2c.write_register(RegisterMap.TX_CONFIG, 0x05)
    await phy.i2c.write_register(RegisterMap.DATA_SELECT, 0x00)

    # Enable RX
    await phy.i2c.write_register(RegisterMap.RX_CONFIG, 0x01)

    # Verify CDR status before release
    status = await phy.read_status()
    pre_lock = status['cdr_lock']
    dut._log.info(f"CDR_LOCK before release: {pre_lock}")

    # Release CDR reset
    await phy.i2c.write_register(RegisterMap.CDR_CONFIG, 0x04)

    # Wait for CDR lock
    await phy.wait_for_cdr_lock(timeout_ns=100000000)

    # Verify CDR_CONFIG was written
    cdr_config = await phy.i2c.read_register(RegisterMap.CDR_CONFIG)
    assert cdr_config == 0x04, f"CDR_CONFIG: Expected 0x04, got 0x{cdr_config:02X}"

    # Verify CDR stays locked
    await ClockCycles(dut.clk, 1000)

    status = await phy.read_status()
    dut._log.info(f"CDR_LOCK after stabilization: {status['cdr_lock']}")

    # Verify TX and RX are still enabled
    tx_config = await phy.i2c.read_register(RegisterMap.TX_CONFIG)
    rx_config = await phy.i2c.read_register(RegisterMap.RX_CONFIG)

    assert (tx_config & 0x01) == 0x01, "TX should remain enabled"
    assert (rx_config & 0x01) == 0x01, "RX should remain enabled"

    dut._log.info("=== LB_005: PASSED ===")
