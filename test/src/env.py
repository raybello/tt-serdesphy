import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
from cocotb.utils import get_sim_time
import random


# ============================================================================
# Configuration Constants
# ============================================================================

class Config:
    """Central configuration for all test parameters"""
    
    # I2C Configuration
    I2C_SLAVE_ADDR = 0x42
    I2C_SCL_PERIOD_NS = 2500
    I2C_SCL_HIGH_TIME_NS = 1000
    I2C_SCL_LOW_TIME_NS = 1500
    I2C_START_STOP_HOLD_TIME_NS = 600
    I2C_START_STOP_SETUP_TIME_NS = 600
    
    # Clock Configuration
    SYS_CLK_PERIOD_NS = 100  # 10MHz system clock
    
    # Timing Configuration
    RESET_CYCLES = 10
    STABILIZATION_CYCLES = 100
    POR_TIMEOUT_CYCLES = 5000
    STATUS_POLL_INTERVAL_CYCLES = 2400  # 100µs at 24MHz
    
    # Test Configuration
    MISSION_MODE_DATA_WORDS = 20
    LOOPBACK_DATA_WORDS = 10


class RegisterMap:
    """Register address definitions"""
    PHY_ENABLE = 0x00
    TX_CONFIG = 0x01
    RX_CONFIG = 0x02
    DATA_SELECT = 0x03
    PLL_CONFIG = 0x04
    CDR_CONFIG = 0x05
    STATUS = 0x06
    CONTROL = 0x07
    
    @classmethod
    def all_registers(cls):
        """Return list of all register addresses"""
        return [cls.PHY_ENABLE, cls.TX_CONFIG, cls.RX_CONFIG, cls.DATA_SELECT,
                cls.PLL_CONFIG, cls.CDR_CONFIG, cls.STATUS, cls.CONTROL]


class PORState:
    """Power-On Reset state definitions"""
    POR_RESET = 0x0
    WAIT_SUPPLY = 0x1
    ANALOG_ISO = 0x2
    DIGITAL_PULSE = 0x3
    ANALOG_PULSE = 0x4
    RELEASE_ISO = 0x5
    READY = 0x6
    ERROR = 0x7
    
    STATE_NAMES = {
        POR_RESET: "POR_RESET",
        WAIT_SUPPLY: "WAIT_SUPPLY",
        ANALOG_ISO: "ANALOG_ISO",
        DIGITAL_PULSE: "DIGITAL_PULSE",
        ANALOG_PULSE: "ANALOG_PULSE",
        RELEASE_ISO: "RELEASE_ISO",
        READY: "READY",
        ERROR: "ERROR"
    }
    
    @classmethod
    def get_name(cls, state_value):
        """Get human-readable state name"""
        return cls.STATE_NAMES.get(state_value, f"UNKNOWN({state_value})")


class StatusBits:
    """Status register bit definitions"""
    PLL_LOCK = 0x01
    CDR_LOCK = 0x02
    TX_FIFO_FULL = 0x04
    TX_FIFO_EMPTY = 0x08
    RX_FIFO_FULL = 0x10
    RX_FIFO_EMPTY = 0x20


# ============================================================================
# I2C Protocol Layer
# ============================================================================

class I2CProtocol:
    """Low-level I2C protocol implementation"""
    
    def __init__(self, dut):
        self.dut = dut
        self.cfg = Config()
    
    async def _set_sda(self, value, output_enable=True):
        """Set SDA line value and output enable"""
        self.dut.sda_out.value = value
        self.dut.sda_oe.value = 1 if output_enable else 0
    
    async def _set_scl(self, value):
        """Set SCL line value"""
        self.dut.scl.value = value
    
    async def start_condition(self):
        """Generate I2C START condition"""
        await self._set_scl(1)
        await self._set_sda(1, True)
        await Timer(2500, unit='ns')
        
        await self._set_sda(0, True)
        await Timer(self.cfg.I2C_START_STOP_HOLD_TIME_NS, unit='ns')
        
        await self._set_scl(0)
        await Timer(self.cfg.I2C_SCL_LOW_TIME_NS, unit='ns')
    
    async def stop_condition(self):
        """Generate I2C STOP condition"""
        await self._set_scl(0)
        await self._set_sda(0, True)
        await Timer(self.cfg.I2C_SCL_LOW_TIME_NS, unit='ns')
        
        await self._set_scl(1)
        await Timer(self.cfg.I2C_START_STOP_HOLD_TIME_NS, unit='ns')
        
        await self._set_sda(1, True)
        await Timer(self.cfg.I2C_START_STOP_SETUP_TIME_NS, unit='ns')
        
        await self._set_sda(1, False)
    
    async def write_byte(self, data):
        """Write one byte to I2C bus, return ACK status"""
        for i in range(8):
            bit = (data >> (7 - i)) & 0x01
            await self._set_sda(bit, True)
            await Timer(self.cfg.I2C_SCL_LOW_TIME_NS, unit='ns')
            
            await self._set_scl(1)
            await Timer(self.cfg.I2C_SCL_HIGH_TIME_NS, unit='ns')
            
            await self._set_scl(0)
            await Timer(self.cfg.I2C_SCL_LOW_TIME_NS, unit='ns')
        
        # Release SDA for ACK
        await self._set_sda(1, False)
        await Timer(750, unit='ns')
        
        # Sample ACK
        await self._set_scl(1)
        await Timer(self.cfg.I2C_SCL_HIGH_TIME_NS, unit='ns')
        
        sda_value = str(self.dut.sda_internal.value)
        ack_received = (sda_value == '0')
        
        await self._set_scl(0)
        await Timer(self.cfg.I2C_SCL_LOW_TIME_NS, unit='ns')
        
        return ack_received
    
    async def read_byte(self, send_ack=True):
        """Read one byte from I2C bus"""
        data = 0
        await self._set_sda(1, False)
        
        for i in range(8):
            await self._set_scl(1)
            await Timer(self.cfg.I2C_SCL_HIGH_TIME_NS, unit='ns')
            
            sda_value = str(self.dut.sda_internal.value)
            bit = 0 if sda_value == '0' else 1
            data = (data << 1) | bit
            
            await self._set_scl(0)
            await Timer(self.cfg.I2C_SCL_LOW_TIME_NS, unit='ns')
        
        # Send ACK/NACK
        await self._set_sda(0 if send_ack else 1, True)
        await Timer(self.cfg.I2C_SCL_LOW_TIME_NS, unit='ns')
        
        await self._set_scl(1)
        await Timer(self.cfg.I2C_SCL_HIGH_TIME_NS, unit='ns')
        
        await self._set_scl(0)
        await Timer(self.cfg.I2C_SCL_LOW_TIME_NS, unit='ns')
        
        await self._set_sda(1, False)
        
        return data


# ============================================================================
# I2C Register Interface
# ============================================================================

class I2CRegisterInterface:
    """High-level I2C register access"""
    
    def __init__(self, dut):
        self.dut = dut
        self.protocol = I2CProtocol(dut)
        self.slave_addr = Config.I2C_SLAVE_ADDR
    
    async def write_register(self, reg_addr, data):
        """Write to an I2C register"""
        await self.protocol.start_condition()
        
        slave_addr_write = (self.slave_addr << 1) | 0
        await self.protocol.write_byte(slave_addr_write)
        await self.protocol.write_byte(reg_addr)
        await self.protocol.write_byte(data)
        
        await self.protocol.stop_condition()
    
    async def read_register(self, reg_addr):
        """Read from an I2C register"""
        await self.protocol.start_condition()
        
        slave_addr_write = (self.slave_addr << 1) | 0
        await self.protocol.write_byte(slave_addr_write)
        await self.protocol.write_byte(reg_addr)
        
        await self.protocol.start_condition()
        
        slave_addr_read = (self.slave_addr << 1) | 1
        await self.protocol.write_byte(slave_addr_read)
        
        data = await self.protocol.read_byte(send_ack=False)
        
        await self.protocol.stop_condition()
        
        return data
    
    async def read_all_registers(self):
        """Read all registers and return as dictionary"""
        values = {}
        for addr in RegisterMap.all_registers():
            values[addr] = await self.read_register(addr)
        return values


# ============================================================================
# PHY Controller
# ============================================================================

class PHYController:
    """High-level PHY configuration and control"""
    
    def __init__(self, dut):
        self.dut = dut
        self.i2c = I2CRegisterInterface(dut)
    
    async def enable_phy(self):
        """Enable PHY and disable isolation"""
        await self.i2c.write_register(RegisterMap.PHY_ENABLE, 0x01)
    
    async def configure_tx(self, enable=True, fifo_enable=False, prbs_enable=False, idle=False):
        """Configure TX block"""
        value = (enable << 0) | (fifo_enable << 1) | (prbs_enable << 2) | (idle << 3)
        await self.i2c.write_register(RegisterMap.TX_CONFIG, value)
    
    async def configure_rx(self, enable=True, fifo_enable=False, prbs_check=False):
        """Configure RX block"""
        value = (enable << 0) | (fifo_enable << 1) | (prbs_check << 2)
        await self.i2c.write_register(RegisterMap.RX_CONFIG, value)
    
    async def configure_data_path(self, tx_source='fifo', rx_source='fifo'):
        """Configure data path routing"""
        tx_sel = 1 if tx_source == 'fifo' else 0
        rx_sel = 1 if rx_source == 'fifo' else 0
        value = (tx_sel << 0) | (rx_sel << 1)
        await self.i2c.write_register(RegisterMap.DATA_SELECT, value)
    
    async def configure_pll(self, reset=False, vco_trim=8):
        """Configure PLL"""
        value = (reset << 7) | (vco_trim & 0x0F)
        await self.i2c.write_register(RegisterMap.PLL_CONFIG, value)
    
    async def configure_cdr(self, reset=False, gain=4):
        """Configure CDR"""
        value = (reset << 7) | (gain & 0x0F)
        await self.i2c.write_register(RegisterMap.CDR_CONFIG, value)
    
    async def read_status(self):
        """Read and parse status register"""
        status = await self.i2c.read_register(RegisterMap.STATUS)
        return {
            'raw': status,
            'pll_lock': bool(status & StatusBits.PLL_LOCK),
            'cdr_lock': bool(status & StatusBits.CDR_LOCK),
            'tx_fifo_full': bool(status & StatusBits.TX_FIFO_FULL),
            'tx_fifo_empty': bool(status & StatusBits.TX_FIFO_EMPTY),
            'rx_fifo_full': bool(status & StatusBits.RX_FIFO_FULL),
            'rx_fifo_empty': bool(status & StatusBits.RX_FIFO_EMPTY)
        }
    
    async def wait_for_lock(self, timeout_ns=2000000, poll_interval_cycles=2400):
        """Poll status until PLL and CDR are locked"""
        start_time = get_sim_time('ns')
        poll_count = 0
        
        while (get_sim_time('ns') - start_time) < timeout_ns:
            status = await self.read_status()
            poll_count += 1
            
            if status['pll_lock'] and status['cdr_lock']:
                elapsed = (get_sim_time('ns') - start_time) / 1e6
                self.dut._log.info(f"✓ PLL and CDR locked after {elapsed:.3f}ms ({poll_count} polls)")
                return True
            
            await ClockCycles(self.dut.clk, poll_interval_cycles)
        
        elapsed = (get_sim_time('ns') - start_time) / 1e6
        self.dut._log.warning(f"✗ Lock timeout after {elapsed:.3f}ms ({poll_count} polls)")
        return False


# ============================================================================
# Test Utilities
# ============================================================================

class TestUtils:
    """Common test utilities and helpers"""
    
    @staticmethod
    async def initialize_signals(dut):
        """Initialize all DUT control signals"""
        dut.ena.value = 1
        dut.rst_n.value = 0
        dut.test_mode.value = 0
        dut.lpbk_en.value = 0
        dut.tx_data.value = 0
        dut.tx_valid.value = 0
        dut.scl.value = 1
        dut.sda_out.value = 1
        dut.sda_oe.value = 0
    
    @staticmethod
    async def reset_sequence(dut):
        """Perform complete reset and POR sequence"""
        dut._log.info("Starting reset sequence")
        
        await TestUtils.initialize_signals(dut)
        await ClockCycles(dut.clk, Config.RESET_CYCLES)
        
        dut.rst_n.value = 1
        await ClockCycles(dut.clk, 20)
        
        # Wait for POR completion
        dut._log.info("Waiting for POR to complete...")
        last_state = None
        
        for cycle in range(Config.POR_TIMEOUT_CYCLES):
            por_state = int(dut.por_state.value)
            por_complete = int(dut.por_complete.value)
            
            if por_state != last_state:
                state_name = PORState.get_name(por_state)
                dut._log.info(f"  POR State: {state_name}")
                last_state = por_state
            
            if por_complete == 1:
                dut._log.info(f"✓ POR completed after {cycle} cycles")
                break
            
            await ClockCycles(dut.clk, 1)
        else:
            dut._log.warning(f"⚠ POR timeout after {Config.POR_TIMEOUT_CYCLES} cycles")
        
        dut._log.info("Reset sequence complete")
    
    @staticmethod
    async def send_data_words(dut, num_words, data_generator=None):
        """Send data words with optional generator"""
        if data_generator is None:
            data_generator = lambda: random.randint(0, 15)
        
        for i in range(num_words):
            data = data_generator()
            dut.tx_data.value = data
            dut.tx_valid.value = 1
            
            await ClockCycles(dut.clk, 1)
            dut.tx_valid.value = 0
            await ClockCycles(dut.clk, 1)
    
    @staticmethod
    def safe_read_rx_data(dut):
        """Safely read RX data handling undefined values"""
        try:
            return int(dut.rx_data.value), int(dut.rx_valid.value)
        except ValueError:
            rx_str = str(dut.rx_data.value)
            if rx_str in ['XXXX', 'ZZZZ', 'UUUU']:
                return 0, 0
            
            clean_str = rx_str.replace('x','0').replace('X','0')
            clean_str = clean_str.replace('z','0').replace('Z','0')
            clean_str = clean_str.replace('u','0').replace('U','0')
            
            try:
                return int(clean_str, 2), 0
            except ValueError:
                return 0, 0
