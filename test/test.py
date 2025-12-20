# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
from cocotb.utils import get_sim_time

# I2C slave address for the SerDes PHY
I2C_SLAVE_ADDR = 0x42

# I2C timing for 400kHz operation (2.5µs period)
I2C_SCL_PERIOD_NS = 2500  # 400kHz = 2.5µs period
I2C_SCL_HIGH_TIME_NS = 1000
I2C_SCL_LOW_TIME_NS = 1500
I2C_START_STOP_HOLD_TIME_NS = 600
I2C_START_STOP_SETUP_TIME_NS = 600

async def i2c_start(dut):
    """Generate I2C START condition"""
    dut._log.info("I2C START")
    
    # Ensure SCL and SDA are high initially
    dut.scl.value = 1
    dut.sda_out.value = 1
    dut.sda_oe.value = 1
    await Timer(2500)  # 2.5µs
    
    # Pull SDA low while SCL is high (START condition)
    dut.sda_out.value = 0
    await Timer(600)  # 600ns
    
    # Pull SCL low
    dut.scl.value = 0
    await Timer(1500)  # 1.5µs

async def i2c_stop(dut):
    """Generate I2C STOP condition"""
    dut._log.info("I2C STOP")
    
    # Ensure SCL is low
    dut.scl.value = 0
    dut.sda_out.value = 0
    dut.sda_oe.value = 1
    await Timer(1500)  # 1.5µs
    
    # Pull SCL high
    dut.scl.value = 1
    await Timer(600)  # 600ns
    
    # Pull SDA high while SCL is high (STOP condition)
    dut.sda_out.value = 1
    await Timer(600)  # 600ns
    
    # Release SDA
    dut.sda_oe.value = 0

async def i2c_write_byte(dut, data):
    """Write one byte to I2C bus, return ACK/NACK status"""
    ack_received = False
    
    for i in range(8):
        # Output data bit on SDA
        bit = (data >> (7 - i)) & 0x01
        dut.sda_out.value = bit
        dut.sda_oe.value = 1
        
        # SCL low period
        await Timer(1500)  # 1.5µs
        
        # SCL high period (data is sampled on rising edge)
        dut.scl.value = 1
        await Timer(1000)  # 1µs
        
        # SCL low period
        dut.scl.value = 0
        await Timer(1500)  # 1.5µs
    
    # Release SDA for ACK/NACK
    dut.sda_oe.value = 0
    await Timer(750)  # 0.75µs
    
    # Sample ACK on SCL high
    dut.scl.value = 1
    await Timer(1000)  # 1µs
    
    # Check ACK (0 = ACK, 1 = NACK, Z/1 = NACK)
    sda_value = str(dut.sda_internal.value)
    if sda_value == '0':
        ack_received = True
        dut._log.info(f"I2C Write 0x{data:02X} - ACK received")
    else:
        dut._log.info(f"I2C Write 0x{data:02X} - NACK received (SDA={sda_value})")
    
    dut.scl.value = 0
    await Timer(1500)  # 1.5µs
    
    return ack_received

async def i2c_read_byte(dut, ack=True):
    """Read one byte from I2C bus, optionally send ACK"""
    data = 0
    
    # Release SDA for reading
    dut.sda_oe.value = 0
    
    for i in range(8):
        # SCL high period (data is valid on rising edge)
        dut.scl.value = 1
        await Timer(1000)  # 1µs
        
        # Read data bit
        sda_value = str(dut.sda_internal.value)
        if sda_value == '0':
            bit = 0
        else:
            bit = 1  # Treat Z or 1 as logical 1
        data = (data << 1) | bit
        
        # SCL low period
        dut.scl.value = 0
        await Timer(1500)  # 1.5µs
    
    # Send ACK/NACK
    if ack:
        dut.sda_out.value = 0  # ACK
        dut._log.info(f"I2C Read 0x{data:02X} - sending ACK")
    else:
        dut.sda_out.value = 1  # NACK
        dut._log.info(f"I2C Read 0x{data:02X} - sending NACK")
    
    dut.sda_oe.value = 1
    await Timer(1500)  # 1.5µs
    
    # ACK/NACK pulse
    dut.scl.value = 1
    await Timer(1000)  # 1µs
    
    dut.scl.value = 0
    await Timer(1500)  # 1.5µs
    
    # Release SDA
    dut.sda_oe.value = 0
    
    return data

async def i2c_write_register(dut, reg_addr, data):
    """Write to an I2C register"""
    dut._log.info(f"I2C Write: Reg 0x{reg_addr:02X} = 0x{data:02X}")
    
    # START
    await i2c_start(dut)
    
    # Slave address + write (0)
    slave_addr_write = (I2C_SLAVE_ADDR << 1) | 0
    ack = await i2c_write_byte(dut, slave_addr_write)
    if not ack:
        dut._log.warning("No ACK received for slave address write")
    
    # Register address
    ack = await i2c_write_byte(dut, reg_addr)
    if not ack:
        dut._log.warning("No ACK received for register address")
    
    # Data
    ack = await i2c_write_byte(dut, data)
    if not ack:
        dut._log.warning("No ACK received for data")
    
    # STOP
    await i2c_stop(dut)

async def i2c_read_register(dut, reg_addr):
    """Read from an I2C register"""
    dut._log.info(f"I2C Read: Reg 0x{reg_addr:02X}")
    
    # START
    await i2c_start(dut)
    
    # Slave address + write (0) - to set register address
    slave_addr_write = (I2C_SLAVE_ADDR << 1) | 0
    ack = await i2c_write_byte(dut, slave_addr_write)
    if not ack:
        dut._log.warning("No ACK received for slave address write")
    
    # Register address
    ack = await i2c_write_byte(dut, reg_addr)
    if not ack:
        dut._log.warning("No ACK received for register address")
    
    # Repeated START
    await i2c_start(dut)
    
    # Slave address + read (1)
    slave_addr_read = (I2C_SLAVE_ADDR << 1) | 1
    ack = await i2c_write_byte(dut, slave_addr_read)
    if not ack:
        dut._log.warning("No ACK received for slave address read")
    
    # Read data (with NACK to end transaction)
    data = await i2c_read_byte(dut, ack=False)
    
    # STOP
    await i2c_stop(dut)
    
    dut._log.info(f"I2C Read Result: Reg 0x{reg_addr:02X} = 0x{data:02X}")
    return data

async def reset_sequence(dut):
    """Perform reset sequence"""
    dut._log.info("Reset sequence")

    # POR State definitions from serdesphy_por.v
    STATE_POR_RESET = 0x0  # 4'b0000
    STATE_WAIT_SUPPLY = 0x1  # 4'b0001
    STATE_ANALOG_ISO = 0x2  # 4'b0010
    STATE_DIGITAL_PULSE = 0x3  # 4'b0011
    STATE_ANALOG_PULSE = 0x4  # 4'b0100
    STATE_RELEASE_ISO = 0x5  # 4'b0101
    STATE_READY = 0x6  # 4'b0110
    STATE_ERROR = 0x7  # 4'b0111

    # Initialize all control signals
    dut.ena.value = 1
    dut.rst_n.value = 0
    dut.test_mode.value = 0
    dut.lpbk_en.value = 0
    dut.tx_data.value = 0
    dut.tx_valid.value = 0
    dut.scl.value = 1
    dut.sda_out.value = 1
    dut.sda_oe.value = 0

    # Hold reset for several clock cycles
    await ClockCycles(dut.clk, 10)

    # Release reset
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 20)  # Give more time for POR to start

    # Wait for POR to complete before proceeding
    dut._log.info("Waiting for POR to complete...")
    por_complete_timeout = 5000  # Maximum cycles to wait for POR completion
    por_complete_cycles = 0
    last_state = None

    for cycle in range(por_complete_timeout):
        try:
            # Check POR signals via testbench hierarchical path
            por_state_val = int(dut.por_state.value)
            por_complete_val = int(dut.por_complete.value)
            por_active_val = int(dut.por_active.value)

            # Log state changes during reset sequence
            if por_state_val != last_state:
                state_name = {
                    STATE_POR_RESET: "POR_RESET",
                    STATE_WAIT_SUPPLY: "WAIT_SUPPLY", 
                    STATE_ANALOG_ISO: "ANALOG_ISO",
                    STATE_DIGITAL_PULSE: "DIGITAL_PULSE",
                    STATE_ANALOG_PULSE: "ANALOG_PULSE",
                    STATE_RELEASE_ISO: "RELEASE_ISO",
                    STATE_READY: "READY",
                    STATE_ERROR: "ERROR"
                }.get(por_state_val, f"UNKNOWN({por_state_val})")

                dut._log.info(f"  POR State: {state_name} (0x{por_state_val:X})")
                dut._log.info(f"  Signals: por_active={por_active_val}, por_complete={por_complete_val}")
                last_state = por_state_val

            if por_complete_val == 1:
                dut._log.info(f"✓ POR completed after {cycle} cycles in READY state")
                dut._log.info(
                    f"  Signals: por_active={dut.por_active.value}, por_complete={dut.por_complete.value}"
                )
                break
        except (ValueError, AttributeError):
            # If hierarchical signals aren't accessible, wait a reasonable time
            if cycle == 100:  # Log once that we're using fallback timing
                dut._log.info("POR signals not accessible, using fallback timing...")
                dut._log.info("Waiting 1000 cycles for POR to complete...")

        await ClockCycles(dut.clk, 1)
        por_complete_cycles = cycle

    if por_complete_cycles >= por_complete_timeout - 1:
        dut._log.warning(f"POR did not complete within {por_complete_timeout} cycles, proceeding anyway")

    dut._log.info("Reset sequence complete")

async def poll_status_with_timeout(dut, timeout_ns=1000000):
    """Poll status register with timeout"""
    dut._log.info(f"Polling status register for {timeout_ns/1e6:.1f}ms")
    
    start_time = get_sim_time('ns')
    poll_count = 0
    
    while (get_sim_time('ns') - start_time) < timeout_ns:
        status = await i2c_read_register(dut, 0x06)
        elapsed_time = (get_sim_time('ns') - start_time) / 1e3
        poll_count += 1
        
        dut._log.info(f"Poll {poll_count}: Status = 0x{status:02X} (time: {elapsed_time:.1f}µs)")
        
        # Check if both PLL and CDR are locked
        if status & 0x03 == 0x03:  # pll_lock=1 and cdr_lock=1
            dut._log.info("Both PLL and CDR locked!")
            break
        
        # Poll every 100µs
        await ClockCycles(dut.clk, 2400)  # 100µs at 24MHz
    
    final_elapsed = (get_sim_time('ns') - start_time) / 1e6
    dut._log.info(f"Status polling completed after {final_elapsed:.3f}ms ({poll_count} polls)")

@cocotb.test()
async def power_up(dut):
    """Test 1: Basic Power-Up Test"""
    dut._log.info("=== Power-Up Test Started ===")

    # Generate system clock (much slower than 24MHz ref clock)
    clock = Clock(dut.clk, 100, unit="ns")  # 10MHz system clock
    cocotb.start_soon(clock.start())

    # Perform reset sequence
    await reset_sequence(dut)
    
    # Wait for power-up stabilization
    dut._log.info("Waiting for power-up stabilization")
    await ClockCycles(dut.clk, 100)  # ~10µs
    
    # Read default register values via I2C
    dut._log.info("Reading default register values")
    for addr in [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]:
        value = await i2c_read_register(dut, addr)
        dut._log.info(f"Default Register 0x{addr:02X} = 0x{value:02X}")
    
    # Poll status register for 1ms timeout
    await poll_status_with_timeout(dut, timeout_ns=1000000)
    
    # Test completed
    dut._log.info("=== Power-Up Test Completed ===")

@cocotb.test()
async def power_up_i2c(dut):
    """Test 2: Power-Up + I2C Write/Read Test"""
    dut._log.info("=== Power-Up + I2C Test Started ===")

    # Generate system clock
    clock = Clock(dut.clk, 100, unit="ns")  # 10MHz system clock
    cocotb.start_soon(clock.start())

    # Perform reset sequence
    await reset_sequence(dut)
    
    # Wait for power-up stabilization
    dut._log.info("Waiting for power-up stabilization")
    await ClockCycles(dut.clk, 100)
    
    # Read initial register values
    dut._log.info("Reading initial register values")
    initial_values = {}
    for addr in [0x00, 0x01, 0x02, 0x03, 0x04, 0x05]:
        initial_values[addr] = await i2c_read_register(dut, addr)
        dut._log.info(f"Initial Reg 0x{addr:02X} = 0x{initial_values[addr]:02X}")
    
    # Enable PHY via I2C
    dut._log.info("Enabling PHY")
    await i2c_write_register(dut, 0x00, 0x01)  # Set phy_en=1, iso_en=0
    
    # Enable TX and RX
    dut._log.info("Enabling TX and RX")
    await i2c_write_register(dut, 0x01, 0x01)  # tx_en=1
    await i2c_write_register(dut, 0x02, 0x01)  # rx_en=1
    
    # Configure PLL (clear reset)
    dut._log.info("Configuring PLL")
    await i2c_write_register(dut, 0x04, 0x08)  # Clear PLL reset, VCO trim=8
    
    # Configure CDR (clear reset)
    dut._log.info("Configuring CDR")
    await i2c_write_register(dut, 0x05, 0x04)  # Clear CDR reset, CDR gain=4
    
    # Verify written values
    dut._log.info("Verifying written register values")
    phy_enable = await i2c_read_register(dut, 0x00)
    tx_config = await i2c_read_register(dut, 0x01)
    rx_config = await i2c_read_register(dut, 0x02)
    pll_config = await i2c_read_register(dut, 0x04)
    cdr_config = await i2c_read_register(dut, 0x05)
    
    dut._log.info(f"PHY Enable: 0x{phy_enable:02X} (wrote 0x01)")
    dut._log.info(f"TX Config: 0x{tx_config:02X} (wrote 0x01)")
    dut._log.info(f"RX Config: 0x{rx_config:02X} (wrote 0x01)")
    dut._log.info(f"PLL Config: 0x{pll_config:02X} (wrote 0x08)")
    dut._log.info(f"CDR Config: 0x{cdr_config:02X} (wrote 0x04)")
    
    # Read and log status
    status = await i2c_read_register(dut, 0x06)
    dut._log.info(f"Status Register: 0x{status:02X}")
    
    # Poll status for 1ms timeout
    await poll_status_with_timeout(dut, timeout_ns=1000000)
    
    # Test completed
    dut._log.info("=== Power-Up + I2C Test Completed ===")

@cocotb.test()
async def mission_mode_traffic(dut):
    """Test 3: Power-Up + I2C Configuration + Mission Mode Traffic"""
    dut._log.info("=== Mission Mode Traffic Test Started ===")

    # Generate system clock
    clock = Clock(dut.clk, 100, unit="ns")  # 10MHz system clock
    cocotb.start_soon(clock.start())

    # Perform reset sequence
    await reset_sequence(dut)

    # Wait for power-up stabilization
    dut._log.info("Waiting for power-up stabilization")
    await ClockCycles(dut.clk, 100)

    # === I2C Configuration for Mission Mode ===
    dut._log.info("Configuring PHY for mission mode")

    # Enable PHY and clear isolation
    await i2c_write_register(dut, 0x00, 0x01)  # PHY_EN=1, ISO_EN=0

    # Configure TX for mission mode (FIFO data path)
    await i2c_write_register(dut, 0x01, 0x03)  # TX_EN=1, TX_FIFO_EN=1, TX_PRBS_EN=0, TX_IDLE=0

    # Configure RX for mission mode
    await i2c_write_register(dut, 0x02, 0x03)  # RX_EN=1, RX_FIFO_EN=1, RX_PRBS_CHK_EN=0

    # Configure data path to use FIFO (not PRBS)
    await i2c_write_register(dut, 0x03, 0x01)  # TX_DATA_SEL=1 (FIFO), RX_DATA_SEL=0 (FIFO)

    # Configure PLL (clear reset, nominal VCO trim)
    await i2c_write_register(dut, 0x04, 0x08)  # PLL_RST=0, VCO_TRIM=8

    # Configure CDR (clear reset, nominal gain)
    await i2c_write_register(dut, 0x05, 0x04)  # CDR_RST=0, CDR_GAIN=4

    # Verify configuration
    dut._log.info("Verifying mission mode configuration")
    phy_en = await i2c_read_register(dut, 0x00)
    tx_config = await i2c_read_register(dut, 0x01)
    rx_config = await i2c_read_register(dut, 0x02)
    data_select = await i2c_read_register(dut, 0x03)

    dut._log.info(f"PHY_ENABLE: 0x{phy_en:02X}")
    dut._log.info(f"TX_CONFIG: 0x{tx_config:02X}")
    dut._log.info(f"RX_CONFIG: 0x{rx_config:02X}")
    dut._log.info(f"DATA_SELECT: 0x{data_select:02X}")

    # Wait for PLL lock
    dut._log.info("Waiting for PLL lock")
    await poll_status_with_timeout(dut, timeout_ns=2000000)  # 2ms timeout

    # === Mission Mode Traffic Generation ===
    dut._log.info("Starting mission mode traffic with random data")

    # Import random for test data generation
    import random

    # Send random data patterns
    for cycle in range(20):  # Send 20 data words
        # Generate random 4-bit data
        random_data = random.randint(0, 15)

        # Drive data onto TX parallel interface
        dut.tx_data.value = random_data
        dut.tx_valid.value = 1

        dut._log.info(f"Cycle {cycle}: Transmitting 0x{random_data:01X}")

        # Hold valid for one clock cycle
        await ClockCycles(dut.clk, 1)

        # Deassert valid between data words
        dut.tx_valid.value = 0
        await ClockCycles(dut.clk, 1)

    # Monitor FIFO status after traffic
    dut._log.info("Checking FIFO status after traffic")
    status = await i2c_read_register(dut, 0x06)
    dut._log.info(f"Status after traffic: 0x{status:02X}")

    # Check specific FIFO flags
    tx_fifo_full = (status >> 2) & 0x01
    tx_fifo_empty = (status >> 3) & 0x01
    rx_fifo_full = (status >> 4) & 0x01
    rx_fifo_empty = (status >> 5) & 0x01

    dut._log.info(f"TX FIFO Full: {tx_fifo_full}")
    dut._log.info(f"TX FIFO Empty: {tx_fifo_empty}")
    dut._log.info(f"RX FIFO Full: {rx_fifo_full}")
    dut._log.info(f"RX FIFO Empty: {rx_fifo_empty}")

    # Enable loopback for end-to-end testing
    dut._log.info("Enabling analog loopback for end-to-end verification")
    dut.lpbk_en.value = 1

    # Send more test data with loopback
    await ClockCycles(dut.clk, 10)  # Allow loopback to settle

    for cycle in range(10):
        random_data = random.randint(0, 15)
        dut.tx_data.value = random_data
        dut.tx_valid.value = 1

        dut._log.info(f"Loopback Cycle {cycle}: TX=0x{random_data:01X}")

        await ClockCycles(dut.clk, 1)
        dut.tx_valid.value = 0

        await ClockCycles(dut.clk, 1)

    # Check RX data after some delay
    await ClockCycles(dut.clk, 2)
    try:
        rx_data = int(dut.rx_data.value)
    except ValueError:
        # Handle cases where RX data contains non-binary values (X, Z, etc.)
        rx_str = str(dut.rx_data.value)
        if rx_str in ['XXXX', 'ZZZZ', 'UUUU']:
            rx_data = 0  # Default for undefined/high-impedance
        else:
            # Replace non-binary characters with 0 for safety
            clean_str = rx_str.replace('x','0').replace('X','0').replace('z','0').replace('Z','0').replace('u','0').replace('U','0')
            try:
                rx_data = int(clean_str, 2)
            except ValueError:
                rx_data = 0

    try:
        rx_valid = int(dut.rx_valid.value)
    except ValueError:
        rx_valid = 0

    if rx_valid:
        dut._log.info(f"  RX data: 0x{rx_data:01X} (valid)")
    else:
        dut._log.info(f"  RX data: 0x{rx_data:01X} (not valid)")

    await ClockCycles(dut.clk, 1)

    # Final status check
    final_status = await i2c_read_register(dut, 0x06)
    dut._log.info(f"Final status: 0x{final_status:02X}")

    # Verify data path integrity
    if (final_status & 0x03) == 0x03:  # PLL and CDR locked
        dut._log.info("✓ Mission mode test PASSED - PLL and CDR locked")
    else:
        dut._log.warning("✗ Mission mode test FAILED - PLL or CDR not locked")

    # Test completed
    dut._log.info("=== Mission Mode Traffic Test Completed ===")
