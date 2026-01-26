# SerDes PHY Common Test Utilities
# Enhanced test infrastructure for comprehensive testing

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer, RisingEdge, FallingEdge, Edge
from cocotb.utils import get_sim_time
import random

# Import base environment
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))
from env import (Config, RegisterMap, PORState, StatusBits,
                 I2CProtocol, I2CRegisterInterface, PHYController, TestUtils)


# ============================================================================
# Extended Configuration Constants
# ============================================================================

class ExtendedConfig(Config):
    """Extended configuration with additional test parameters"""

    # POR Timing
    POR_SUPPLY_STABLE_CYCLES = 48  # ~2us at 24MHz
    POR_RESET_HOLD_CYCLES = 24     # ~1us
    POR_RELEASE_DELAY_CYCLES = 12  # ~0.5us

    # Clock timing
    REF_CLK_PERIOD_NS = 42         # 24MHz = 41.67ns
    TX_CLK_PERIOD_NS = 4.17        # 240MHz

    # FIFO parameters
    FIFO_DEPTH = 8
    FIFO_FULL_THRESHOLD = 7

    # PRBS parameters
    PRBS7_LENGTH = 127

    # Loopback timing
    LOOPBACK_SETTLE_CYCLES = 100

    # Lock timing
    PLL_LOCK_TIMEOUT_US = 10
    CDR_LOCK_TIMEOUT_US = 100


class RegisterDefaults:
    """Default register values after reset"""
    PHY_ENABLE = 0x02     # PHY_EN=0, ISO_EN=1
    TX_CONFIG = 0x00
    RX_CONFIG = 0x00
    DATA_SELECT = 0x00
    PLL_CONFIG = 0x48     # VCO_TRIM=8, PLL_RST=1
    CDR_CONFIG = 0x14     # CDR_GAIN=4, CDR_RST=1
    STATUS = 0x00
    DEBUG_ENABLE = 0x00


class StatusBitsExtended(StatusBits):
    """Extended status bit definitions"""
    PLL_LOCK = 0x01       # Bit 0
    CDR_LOCK = 0x02       # Bit 1
    TX_FIFO_FULL = 0x04   # Bit 2
    TX_FIFO_EMPTY = 0x08  # Bit 3
    RX_FIFO_FULL = 0x10   # Bit 4
    RX_FIFO_EMPTY = 0x20  # Bit 5
    PRBS_ERR = 0x40       # Bit 6
    FIFO_ERR = 0x80       # Bit 7


# ============================================================================
# Enhanced I2C Protocol with Timing Variations
# ============================================================================

class I2CProtocolExtended(I2CProtocol):
    """Extended I2C protocol with configurable timing"""

    def __init__(self, dut, scl_period_ns=None, scl_high_ns=None, scl_low_ns=None):
        super().__init__(dut)
        self.scl_period_ns = scl_period_ns or Config.I2C_SCL_PERIOD_NS
        self.scl_high_ns = scl_high_ns or Config.I2C_SCL_HIGH_TIME_NS
        self.scl_low_ns = scl_low_ns or Config.I2C_SCL_LOW_TIME_NS

    async def start_condition_with_timing(self, hold_time_ns=None):
        """Generate START with configurable hold time"""
        hold_time = hold_time_ns or self.cfg.I2C_START_STOP_HOLD_TIME_NS

        await self._set_scl(1)
        await self._set_sda(1, True)
        await Timer(self.scl_high_ns, unit='ns')

        await self._set_sda(0, True)
        await Timer(hold_time, unit='ns')

        await self._set_scl(0)
        await Timer(self.scl_low_ns, unit='ns')

    async def stop_condition_with_timing(self, setup_time_ns=None):
        """Generate STOP with configurable setup time"""
        setup_time = setup_time_ns or self.cfg.I2C_START_STOP_SETUP_TIME_NS

        await self._set_scl(0)
        await self._set_sda(0, True)
        await Timer(self.scl_low_ns, unit='ns')

        await self._set_scl(1)
        await Timer(setup_time, unit='ns')

        await self._set_sda(1, True)
        await Timer(setup_time, unit='ns')

        await self._set_sda(1, False)

    async def write_byte_with_timing(self, data, sda_setup_ns=100):
        """Write byte with configurable SDA setup time"""
        for i in range(8):
            bit = (data >> (7 - i)) & 0x01
            await self._set_sda(bit, True)
            await Timer(sda_setup_ns, unit='ns')  # SDA setup time

            await self._set_scl(1)
            await Timer(self.scl_high_ns, unit='ns')

            await self._set_scl(0)
            await Timer(self.scl_low_ns, unit='ns')

        # Release SDA for ACK
        await self._set_sda(1, False)
        await Timer(sda_setup_ns, unit='ns')

        # Sample ACK
        await self._set_scl(1)
        await Timer(self.scl_high_ns, unit='ns')

        sda_value = str(self.dut.sda_internal.value)
        ack_received = (sda_value == '0')

        await self._set_scl(0)
        await Timer(self.scl_low_ns, unit='ns')

        return ack_received


class I2CRegisterInterfaceExtended(I2CRegisterInterface):
    """Extended I2C register interface with advanced operations"""

    def __init__(self, dut, slave_addr=None):
        super().__init__(dut)
        self.slave_addr = slave_addr or Config.I2C_SLAVE_ADDR
        self.protocol_extended = I2CProtocolExtended(dut)

    async def write_register_check_ack(self, reg_addr, data):
        """Write register and return ACK status for each byte"""
        acks = []

        await self.protocol.start_condition()

        slave_addr_write = (self.slave_addr << 1) | 0
        acks.append(await self.protocol.write_byte(slave_addr_write))
        acks.append(await self.protocol.write_byte(reg_addr))
        acks.append(await self.protocol.write_byte(data))

        await self.protocol.stop_condition()

        return acks

    async def write_register_wrong_addr(self, wrong_addr, reg_addr, data):
        """Write to wrong slave address (should get NACK)"""
        await self.protocol.start_condition()

        slave_addr_write = (wrong_addr << 1) | 0
        ack = await self.protocol.write_byte(slave_addr_write)

        await self.protocol.stop_condition()

        return ack

    async def read_register_repeated_start(self, reg_addr):
        """Read with proper repeated START sequence"""
        await self.protocol.start_condition()

        slave_addr_write = (self.slave_addr << 1) | 0
        await self.protocol.write_byte(slave_addr_write)
        await self.protocol.write_byte(reg_addr)

        # Repeated START
        await self.protocol.start_condition()

        slave_addr_read = (self.slave_addr << 1) | 1
        await self.protocol.write_byte(slave_addr_read)

        data = await self.protocol.read_byte(send_ack=False)

        await self.protocol.stop_condition()

        return data


# ============================================================================
# Enhanced PHY Controller
# ============================================================================

class PHYControllerExtended(PHYController):
    """Extended PHY controller with additional features"""

    def __init__(self, dut):
        super().__init__(dut)
        self.i2c = I2CRegisterInterfaceExtended(dut)

    async def full_initialization(self):
        """Perform full PHY initialization sequence per datasheet"""
        # Step 3: Enable PHY
        await self.i2c.write_register(RegisterMap.PHY_ENABLE, 0x01)

        # Step 4: Release PLL reset
        await self.i2c.write_register(RegisterMap.PLL_CONFIG, 0x08)  # VCO_TRIM=8, PLL_RST=0

        # Step 5: Wait for PLL lock
        pll_locked = await self.wait_for_pll_lock()
        if not pll_locked:
            return False

        # Step 6: Configure TX
        await self.i2c.write_register(RegisterMap.TX_CONFIG, 0x05)  # TX_EN + TX_PRBS_EN

        # Step 7: Configure data path
        await self.i2c.write_register(RegisterMap.DATA_SELECT, 0x00)  # PRBS source

        # Step 8: Release CDR reset
        await self.i2c.write_register(RegisterMap.CDR_CONFIG, 0x04)  # CDR_RST=0

        # Step 9: Configure RX
        await self.i2c.write_register(RegisterMap.RX_CONFIG, 0x05)  # RX_EN + RX_PRBS_CHK_EN

        # Step 10: Wait for CDR lock
        cdr_locked = await self.wait_for_cdr_lock()

        return cdr_locked

    async def wait_for_pll_lock(self, timeout_ns=10000000, poll_interval_cycles=100):
        """Wait for PLL lock only"""
        start_time = get_sim_time('ns')

        while (get_sim_time('ns') - start_time) < timeout_ns:
            status = await self.read_status()
            if status['pll_lock']:
                return True
            await ClockCycles(self.dut.clk, poll_interval_cycles)

        return False

    async def wait_for_cdr_lock(self, timeout_ns=100000000, poll_interval_cycles=100):
        """Wait for CDR lock only"""
        start_time = get_sim_time('ns')

        while (get_sim_time('ns') - start_time) < timeout_ns:
            status = await self.read_status()
            if status['cdr_lock']:
                return True
            await ClockCycles(self.dut.clk, poll_interval_cycles)

        return False

    async def read_status_extended(self):
        """Read and parse all status bits"""
        status = await self.i2c.read_register(RegisterMap.STATUS)
        return {
            'raw': status,
            'pll_lock': bool(status & StatusBitsExtended.PLL_LOCK),
            'cdr_lock': bool(status & StatusBitsExtended.CDR_LOCK),
            'tx_fifo_full': bool(status & StatusBitsExtended.TX_FIFO_FULL),
            'tx_fifo_empty': bool(status & StatusBitsExtended.TX_FIFO_EMPTY),
            'rx_fifo_full': bool(status & StatusBitsExtended.RX_FIFO_FULL),
            'rx_fifo_empty': bool(status & StatusBitsExtended.RX_FIFO_EMPTY),
            'prbs_err': bool(status & StatusBitsExtended.PRBS_ERR),
            'fifo_err': bool(status & StatusBitsExtended.FIFO_ERR),
        }

    async def configure_pll_full(self, vco_trim=8, cp_current=2, reset=False, bypass=False):
        """Configure PLL with all parameters"""
        value = (vco_trim & 0x0F) | ((cp_current & 0x03) << 4) | (reset << 6) | (bypass << 7)
        await self.i2c.write_register(RegisterMap.PLL_CONFIG, value)

    async def configure_cdr_full(self, gain=4, fast_lock=False, reset=False):
        """Configure CDR with all parameters"""
        value = (gain & 0x07) | (fast_lock << 3) | (reset << 4)
        await self.i2c.write_register(RegisterMap.CDR_CONFIG, value)


# ============================================================================
# Enhanced Test Utilities
# ============================================================================

class TestUtilsExtended(TestUtils):
    """Extended test utilities with additional capabilities"""

    @staticmethod
    async def initialize_with_supplies(dut, dvdd_ok=True, avdd_ok=True):
        """Initialize signals including supply monitoring"""
        await TestUtils.initialize_signals(dut)
        # Supply signals if accessible
        try:
            dut.dvdd_ok.value = 1 if dvdd_ok else 0
            dut.avdd_ok.value = 1 if avdd_ok else 0
        except AttributeError:
            pass  # Supply signals may not be directly accessible

    @staticmethod
    async def wait_for_por_state(dut, target_state, timeout_cycles=5000):
        """Wait for POR to reach specific state"""
        for _ in range(timeout_cycles):
            try:
                por_state = int(dut.por_state.value)
                if por_state == target_state:
                    return True
            except ValueError:
                pass
            await ClockCycles(dut.clk, 1)
        return False

    @staticmethod
    async def get_por_signals(dut):
        """Read all POR-related signals"""
        try:
            return {
                'state': int(dut.por_state.value),
                'por_active': int(dut.por_active.value),
                'por_complete': int(dut.por_complete.value),
                'power_good': int(dut.power_good.value),
                'analog_iso_n': int(dut.analog_iso_n.value),
                'digital_reset_n': int(dut.digital_reset_n.value),
                'analog_reset_n': int(dut.analog_reset_n.value),
            }
        except (ValueError, AttributeError):
            return None

    @staticmethod
    async def send_prbs_data(dut, num_words):
        """Send PRBS-like data pattern"""
        lfsr = 0x7F  # Initial seed for PRBS-7

        for _ in range(num_words):
            # PRBS-7: x^7 + x^6 + 1
            feedback = ((lfsr >> 6) ^ (lfsr >> 5)) & 1
            lfsr = ((lfsr << 1) | feedback) & 0x7F

            data = lfsr & 0x0F
            dut.tx_data.value = data
            dut.tx_valid.value = 1
            await ClockCycles(dut.clk, 1)
            dut.tx_valid.value = 0
            await ClockCycles(dut.clk, 1)

    @staticmethod
    async def fill_tx_fifo(dut, num_words=8):
        """Fill TX FIFO to specified level"""
        for i in range(num_words):
            dut.tx_data.value = i & 0x0F
            dut.tx_valid.value = 1
            await ClockCycles(dut.clk, 1)
            dut.tx_valid.value = 0
            await ClockCycles(dut.clk, 1)

    @staticmethod
    async def verify_manchester_encoding(data_byte):
        """Verify Manchester encoding for a byte"""
        # Logic 0 = High-to-Low (10)
        # Logic 1 = Low-to-High (01)
        manchester = 0
        for i in range(8):
            bit = (data_byte >> (7 - i)) & 1
            if bit == 0:
                manchester = (manchester << 2) | 0b10  # H-to-L
            else:
                manchester = (manchester << 2) | 0b01  # L-to-H
        return manchester

    @staticmethod
    def generate_test_pattern(pattern_type, length=8):
        """Generate test data patterns"""
        if pattern_type == 'walking_ones':
            return [1 << (i % 4) for i in range(length)]
        elif pattern_type == 'walking_zeros':
            return [(~(1 << (i % 4))) & 0x0F for i in range(length)]
        elif pattern_type == 'alternating':
            return [0x0A if i % 2 == 0 else 0x05 for i in range(length)]
        elif pattern_type == 'all_zeros':
            return [0x00] * length
        elif pattern_type == 'all_ones':
            return [0x0F] * length
        elif pattern_type == 'random':
            return [random.randint(0, 15) for _ in range(length)]
        else:
            return list(range(length))


# ============================================================================
# Test Result Tracking
# ============================================================================

class TestResult:
    """Track test results"""

    def __init__(self, test_id, description):
        self.test_id = test_id
        self.description = description
        self.passed = False
        self.message = ""
        self.start_time = None
        self.end_time = None

    def start(self):
        self.start_time = get_sim_time('ns')

    def finish(self, passed, message=""):
        self.end_time = get_sim_time('ns')
        self.passed = passed
        self.message = message

    def duration_ns(self):
        if self.start_time and self.end_time:
            return self.end_time - self.start_time
        return 0

    def __str__(self):
        status = "PASS" if self.passed else "FAIL"
        return f"[{self.test_id}] {status}: {self.description} - {self.message}"


class TestSuite:
    """Collection of test results"""

    def __init__(self, name):
        self.name = name
        self.results = []

    def add_result(self, result):
        self.results.append(result)

    def summary(self):
        total = len(self.results)
        passed = sum(1 for r in self.results if r.passed)
        failed = total - passed
        return f"{self.name}: {passed}/{total} passed, {failed} failed"


# ============================================================================
# Common Test Setup/Teardown
# ============================================================================

async def common_test_setup(dut, start_clock=True, perform_reset=True):
    """Common test setup sequence"""
    dut._log.info("=== Test Setup Started ===")

    if start_clock:
        clock = Clock(dut.clk, Config.SYS_CLK_PERIOD_NS, unit="ns")
        cocotb.start_soon(clock.start())

    if perform_reset:
        await TestUtils.reset_sequence(dut)
        await ClockCycles(dut.clk, Config.STABILIZATION_CYCLES)

    dut._log.info("=== Test Setup Complete ===")


async def common_test_teardown(dut):
    """Common test teardown sequence"""
    dut._log.info("=== Test Teardown ===")
    # Any cleanup needed
    await ClockCycles(dut.clk, 10)


# Export all
__all__ = [
    'Config', 'ExtendedConfig', 'RegisterMap', 'RegisterDefaults',
    'PORState', 'StatusBits', 'StatusBitsExtended',
    'I2CProtocol', 'I2CProtocolExtended',
    'I2CRegisterInterface', 'I2CRegisterInterfaceExtended',
    'PHYController', 'PHYControllerExtended',
    'TestUtils', 'TestUtilsExtended',
    'TestResult', 'TestSuite',
    'common_test_setup', 'common_test_teardown',
    'Clock', 'ClockCycles', 'Timer', 'RisingEdge', 'FallingEdge', 'Edge',
    'get_sim_time', 'random', 'cocotb'
]
