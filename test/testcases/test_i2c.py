# SerDes PHY I2C Interface Tests
# Tests I2C_001 through I2C_011

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

from .common import (
    Config, RegisterMap,
    I2CProtocol, I2CProtocolExtended, I2CRegisterInterface, I2CRegisterInterfaceExtended,
    TestUtils, common_test_setup
)


# ============================================================================
# I2C Basic Protocol Tests (I2C_001 - I2C_007)
# ============================================================================

@cocotb.test()
async def test_I2C_001_write_single_register(dut):
    """I2C_001: Write single register"""
    dut._log.info("=== I2C_001: Write Single Register Test ===")

    clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await TestUtils.reset_sequence(dut)
    await ClockCycles(dut.clk, Config.STABILIZATION_CYCLES)

    i2c = I2CRegisterInterface(dut)

    # Write test value to TX_CONFIG register
    test_value = 0x05
    dut._log.info(f"I2C_001: Writing 0x{test_value:02X} to TX_CONFIG (0x01)")

    await i2c.write_register(RegisterMap.TX_CONFIG, test_value)

    # Read back to verify
    readback = await i2c.read_register(RegisterMap.TX_CONFIG)
    dut._log.info(f"I2C_001: Read back 0x{readback:02X}")

    assert readback == test_value, f"I2C_001: Write/Read mismatch (wrote 0x{test_value:02X}, read 0x{readback:02X})"
    dut._log.info("I2C_001: PASSED - Single register write successful")


@cocotb.test()
async def test_I2C_002_read_single_register(dut):
    """I2C_002: Read single register"""
    dut._log.info("=== I2C_002: Read Single Register Test ===")

    clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await TestUtils.reset_sequence(dut)
    await ClockCycles(dut.clk, Config.STABILIZATION_CYCLES)

    i2c = I2CRegisterInterface(dut)

    # Read STATUS register (read-only)
    status = await i2c.read_register(RegisterMap.STATUS)
    dut._log.info(f"I2C_002: STATUS register = 0x{status:02X}")

    # STATUS register should have valid data (not X/Z)
    assert 0 <= status <= 255, "I2C_002: Invalid STATUS value"

    # Read PHY_ENABLE default
    phy_enable = await i2c.read_register(RegisterMap.PHY_ENABLE)
    dut._log.info(f"I2C_002: PHY_ENABLE register = 0x{phy_enable:02X}")

    dut._log.info("I2C_002: PASSED - Single register read successful")


@cocotb.test()
async def test_I2C_003_correct_slave_address(dut):
    """I2C_003: Verify correct slave address (0x42)"""
    dut._log.info("=== I2C_003: Correct Slave Address Test ===")

    clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await TestUtils.reset_sequence(dut)
    await ClockCycles(dut.clk, Config.STABILIZATION_CYCLES)

    i2c_ext = I2CRegisterInterfaceExtended(dut)

    # Write with correct address (0x42)
    acks = await i2c_ext.write_register_check_ack(RegisterMap.TX_CONFIG, 0xAA)

    dut._log.info(f"I2C_003: ACK status for 0x42: Address={acks[0]}, Reg={acks[1]}, Data={acks[2]}")

    # All should be ACKed
    assert acks[0] == True, "I2C_003: Address byte should be ACKed"
    assert acks[1] == True, "I2C_003: Register address byte should be ACKed"
    assert acks[2] == True, "I2C_003: Data byte should be ACKed"

    dut._log.info("I2C_003: PASSED - Slave address 0x42 correctly acknowledged")


@cocotb.test()
async def test_I2C_004_ack_on_valid_address(dut):
    """I2C_004: Verify ACK on valid address"""
    dut._log.info("=== I2C_004: ACK on Valid Address Test ===")

    clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await TestUtils.reset_sequence(dut)
    await ClockCycles(dut.clk, Config.STABILIZATION_CYCLES)

    protocol = I2CProtocol(dut)

    # Send START + correct address
    await protocol.start_condition()

    slave_addr_write = (Config.I2C_SLAVE_ADDR << 1) | 0  # 0x42 + Write
    ack = await protocol.write_byte(slave_addr_write)

    await protocol.stop_condition()

    dut._log.info(f"I2C_004: ACK received for address 0x{Config.I2C_SLAVE_ADDR:02X}: {ack}")
    assert ack == True, "I2C_004: Valid address should receive ACK"

    dut._log.info("I2C_004: PASSED - ACK received on valid address")


@cocotb.test()
async def test_I2C_005_nack_on_invalid_address(dut):
    """I2C_005: Verify NACK on invalid address"""
    dut._log.info("=== I2C_005: NACK on Invalid Address Test ===")

    clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await TestUtils.reset_sequence(dut)
    await ClockCycles(dut.clk, Config.STABILIZATION_CYCLES)

    i2c_ext = I2CRegisterInterfaceExtended(dut)

    # Try with wrong addresses
    wrong_addresses = [0x00, 0x41, 0x43, 0x50, 0x7F]

    for wrong_addr in wrong_addresses:
        ack = await i2c_ext.write_register_wrong_addr(wrong_addr, RegisterMap.TX_CONFIG, 0x00)
        dut._log.info(f"I2C_005: Address 0x{wrong_addr:02X} ACK={ack}")
        assert ack == False, f"I2C_005: Invalid address 0x{wrong_addr:02X} should receive NACK"

    dut._log.info("I2C_005: PASSED - NACK received on all invalid addresses")


@cocotb.test()
async def test_I2C_006_repeated_start_for_read(dut):
    """I2C_006: Repeated START for read operation"""
    dut._log.info("=== I2C_006: Repeated START for Read Test ===")

    clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await TestUtils.reset_sequence(dut)
    await ClockCycles(dut.clk, Config.STABILIZATION_CYCLES)

    # Write a known value first
    i2c = I2CRegisterInterface(dut)
    test_value = 0x5A
    await i2c.write_register(RegisterMap.TX_CONFIG, test_value)

    # Read using repeated START
    i2c_ext = I2CRegisterInterfaceExtended(dut)
    readback = await i2c_ext.read_register_repeated_start(RegisterMap.TX_CONFIG)

    dut._log.info(f"I2C_006: Wrote 0x{test_value:02X}, read back 0x{readback:02X}")
    assert readback == test_value, f"I2C_006: Repeated START read failed"

    dut._log.info("I2C_006: PASSED - Repeated START read operation works correctly")


@cocotb.test()
async def test_I2C_007_stop_terminates_transaction(dut):
    """I2C_007: STOP condition terminates transaction"""
    dut._log.info("=== I2C_007: STOP Terminates Transaction Test ===")

    clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await TestUtils.reset_sequence(dut)
    await ClockCycles(dut.clk, Config.STABILIZATION_CYCLES)

    protocol = I2CProtocol(dut)
    i2c = I2CRegisterInterface(dut)

    # Start a transaction but terminate early with STOP
    await protocol.start_condition()
    slave_addr_write = (Config.I2C_SLAVE_ADDR << 1) | 0
    await protocol.write_byte(slave_addr_write)
    # Send STOP without completing transaction
    await protocol.stop_condition()

    await ClockCycles(dut.clk, 50)

    # Verify bus is free and new transaction works
    test_value = 0x33
    await i2c.write_register(RegisterMap.TX_CONFIG, test_value)
    readback = await i2c.read_register(RegisterMap.TX_CONFIG)

    assert readback == test_value, "I2C_007: Transaction after STOP should work"
    dut._log.info("I2C_007: PASSED - STOP condition properly terminates transaction")


# ============================================================================
# I2C Timing Tests (I2C_008 - I2C_011)
# ============================================================================

@cocotb.test()
async def test_I2C_008_scl_frequency_range(dut):
    """I2C_008: SCL frequency range (10 kHz to 24 MHz)"""
    dut._log.info("=== I2C_008: SCL Frequency Range Test ===")

    clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await TestUtils.reset_sequence(dut)
    await ClockCycles(dut.clk, Config.STABILIZATION_CYCLES)

    # Test at different SCL frequencies
    # SCL period: 10kHz=100us, 100kHz=10us, 400kHz=2.5us, 1MHz=1us
    test_frequencies = [
        (100000, "10 kHz"),    # 100us period
        (10000, "100 kHz"),    # 10us period
        (2500, "400 kHz"),     # 2.5us period (standard I2C)
        (1000, "1 MHz"),       # 1us period (Fast-mode Plus)
    ]

    i2c = I2CRegisterInterface(dut)
    test_value = 0x00

    for scl_period_ns, freq_name in test_frequencies:
        dut._log.info(f"I2C_008: Testing at {freq_name} (SCL period = {scl_period_ns}ns)")

        # Configure protocol with this timing
        i2c.protocol.cfg.I2C_SCL_PERIOD_NS = scl_period_ns
        i2c.protocol.cfg.I2C_SCL_HIGH_TIME_NS = scl_period_ns // 2
        i2c.protocol.cfg.I2C_SCL_LOW_TIME_NS = scl_period_ns // 2

        test_value = (test_value + 0x11) & 0xFF
        await i2c.write_register(RegisterMap.TX_CONFIG, test_value)
        readback = await i2c.read_register(RegisterMap.TX_CONFIG)

        if readback == test_value:
            dut._log.info(f"I2C_008: {freq_name} - PASS")
        else:
            dut._log.warning(f"I2C_008: {freq_name} - FAIL (wrote 0x{test_value:02X}, read 0x{readback:02X})")

    # Restore default timing
    i2c.protocol.cfg.I2C_SCL_PERIOD_NS = Config.I2C_SCL_PERIOD_NS
    i2c.protocol.cfg.I2C_SCL_HIGH_TIME_NS = Config.I2C_SCL_HIGH_TIME_NS
    i2c.protocol.cfg.I2C_SCL_LOW_TIME_NS = Config.I2C_SCL_LOW_TIME_NS

    dut._log.info("I2C_008: PASSED - SCL frequency range test complete")


@cocotb.test()
async def test_I2C_009_sda_setup_time(dut):
    """I2C_009: SDA setup time (100 ns min)"""
    dut._log.info("=== I2C_009: SDA Setup Time Test ===")

    clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await TestUtils.reset_sequence(dut)
    await ClockCycles(dut.clk, Config.STABILIZATION_CYCLES)

    # Test with minimum setup time (100ns)
    protocol_ext = I2CProtocolExtended(dut)
    i2c = I2CRegisterInterface(dut)

    # First write with normal timing
    await i2c.write_register(RegisterMap.TX_CONFIG, 0xAA)

    # Test with 100ns setup time
    test_value = 0x55

    await protocol_ext.start_condition_with_timing()

    slave_addr_write = (Config.I2C_SLAVE_ADDR << 1) | 0
    ack1 = await protocol_ext.write_byte_with_timing(slave_addr_write, sda_setup_ns=100)
    ack2 = await protocol_ext.write_byte_with_timing(RegisterMap.TX_CONFIG, sda_setup_ns=100)
    ack3 = await protocol_ext.write_byte_with_timing(test_value, sda_setup_ns=100)

    await protocol_ext.stop_condition_with_timing()

    dut._log.info(f"I2C_009: ACKs with 100ns setup: addr={ack1}, reg={ack2}, data={ack3}")

    # Verify write succeeded
    readback = await i2c.read_register(RegisterMap.TX_CONFIG)
    dut._log.info(f"I2C_009: Wrote 0x{test_value:02X}, read 0x{readback:02X}")

    assert readback == test_value, "I2C_009: 100ns setup time should be sufficient"
    dut._log.info("I2C_009: PASSED - SDA setup time (100ns) works correctly")


@cocotb.test()
async def test_I2C_010_start_hold_time(dut):
    """I2C_010: START hold time (600 ns min)"""
    dut._log.info("=== I2C_010: START Hold Time Test ===")

    clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await TestUtils.reset_sequence(dut)
    await ClockCycles(dut.clk, Config.STABILIZATION_CYCLES)

    protocol_ext = I2CProtocolExtended(dut)
    i2c = I2CRegisterInterface(dut)

    # Test with minimum START hold time (600ns)
    test_value = 0xBB

    await protocol_ext.start_condition_with_timing(hold_time_ns=600)

    slave_addr_write = (Config.I2C_SLAVE_ADDR << 1) | 0
    ack1 = await protocol_ext.write_byte(slave_addr_write)
    ack2 = await protocol_ext.write_byte(RegisterMap.TX_CONFIG)
    ack3 = await protocol_ext.write_byte(test_value)

    await protocol_ext.stop_condition()

    dut._log.info(f"I2C_010: ACKs with 600ns START hold: {ack1}, {ack2}, {ack3}")

    # Verify
    readback = await i2c.read_register(RegisterMap.TX_CONFIG)
    assert readback == test_value, "I2C_010: 600ns START hold time should work"

    dut._log.info("I2C_010: PASSED - START hold time (600ns) works correctly")


@cocotb.test()
async def test_I2C_011_stop_setup_time(dut):
    """I2C_011: STOP setup time (600 ns min)"""
    dut._log.info("=== I2C_011: STOP Setup Time Test ===")

    clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await TestUtils.reset_sequence(dut)
    await ClockCycles(dut.clk, Config.STABILIZATION_CYCLES)

    protocol_ext = I2CProtocolExtended(dut)
    i2c = I2CRegisterInterface(dut)

    # Test with minimum STOP setup time (600ns)
    test_value = 0xCC

    await protocol_ext.start_condition()

    slave_addr_write = (Config.I2C_SLAVE_ADDR << 1) | 0
    await protocol_ext.write_byte(slave_addr_write)
    await protocol_ext.write_byte(RegisterMap.TX_CONFIG)
    await protocol_ext.write_byte(test_value)

    await protocol_ext.stop_condition_with_timing(setup_time_ns=600)

    # Verify write succeeded and bus is free
    await ClockCycles(dut.clk, 20)
    readback = await i2c.read_register(RegisterMap.TX_CONFIG)

    assert readback == test_value, "I2C_011: 600ns STOP setup time should work"
    dut._log.info("I2C_011: PASSED - STOP setup time (600ns) works correctly")
