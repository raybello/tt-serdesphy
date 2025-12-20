
module serdesphy_top(
	// Reset & Clock
	input 	clk_ref_24m,
	input 	rst_n,
	output 	pll_lock,
	// CSR Interface
	inout 	sda,
	input 	scl,
	// Transmit
	input 	[3:0]	tx_data,
	input 	tx_valid,
	output	txp,
	output	txn,
	// Receive
	output 	[3:0]	rx_data,
	output 	rx_valid,
	output 	cdr_lock,
	output 	prbs_err,
	input	rxp,
	input	rxn,
	// Configuration
	input 	test_mode,
	input	lpbk_en,
	output	dbg_ana,
	// Additional Status Outputs
	output 	tx_active,
	output 	tx_error,
	output 	rx_active,
	output 	rx_error,
	output 	rx_aligned,
	output 	phy_ready,
	// Power Monitoring Inputs
	input 	dvdd_ok,
	input 	avdd_ok
	);

	// Internal clocks
	wire clk_240m_tx;
	wire clk_240m_rx;
	
	wire rst_n_24m;
	wire rst_n_240m_tx;
	wire rst_n_240m_rx;
	
	// Power-on-Reset signals
	wire power_good;
	wire analog_iso_n;
	wire digital_reset_n;
	wire analog_reset_n;
	wire por_active;
	wire por_complete;
	
	// PLL Control signals
	wire phy_en;
	wire iso_en;
	wire [3:0] vco_trim;
	wire [1:0] cp_current;
	wire pll_rst;
	wire pll_bypass;
	wire [2:0] cdr_gain;
	wire cdr_fast_lock;
	wire cdr_rst;
	wire pll_ready;
	wire [7:0] pll_status;
	wire pll_error;
	wire clk_24m_en;
	wire clk_240m_tx_en;
	wire clk_240m_rx_en;
	
	// CSR Control signals
	wire tx_en;
	wire tx_fifo_en;
	wire tx_prbs_en;
	wire tx_idle;
	wire rx_en;
	wire rx_fifo_en;
	wire rx_prbs_chk_en;
	wire rx_align_rst;
	wire tx_data_sel;
	wire rx_data_sel;
	
	// Debug signals
	wire dbg_vctrl;
	wire dbg_pd;
	wire dbg_fifo;
	
	// TX Interface signals
	wire tx_serial_data;
	wire tx_serial_valid;
	wire tx_idle_pattern;
	wire tx_fifo_full;
	wire tx_fifo_empty;
	wire tx_overflow;
	wire tx_underflow;
	wire if_error_tx;
	
	// RX Interface signals
	wire rx_serial_data;
	wire rx_serial_valid;
	wire rx_serial_error;
	wire rx_fifo_full;
	wire rx_fifo_empty;
	wire rx_overflow;
	wire rx_underflow;
	
	// PCS to PMA interface signals
	wire pll_enable;
	wire pll_reset_n;
	wire pll_bypass_en;
	wire pll_iso_n;
	wire serializer_enable;
	wire serializer_clock;
	wire serializer_reset_n;
	wire deserializer_enable;
	wire deserializer_clock;
	wire deserializer_reset_n;
	wire deserializer_data;
	
	// PMA to PCS interface signals
	wire serializer_ready;
	wire serializer_error;
	wire deserializer_ready;
	wire deserializer_lock;
	wire deserializer_error;
	wire deserializer_active;
	wire deserializer_status;
	
	// Analog interface signals (simplified models)
	wire pll_lock_raw;
	wire pll_vco_ok;
	wire pll_cp_ok;
	
	// PCS Internal Logic - Connect RX serial data from PMA
	assign rx_serial_data = deserializer_data;
	
	// PCS Internal Logic - Generate PMA control signals
	assign pll_enable = phy_en && !iso_en;
	assign pll_reset_n = digital_reset_n && !pll_rst;
	assign pll_bypass_en = pll_bypass;
	assign pll_iso_n = analog_iso_n;
	
	// Serializer control signals
	assign serializer_enable = tx_en && !iso_en;
	assign serializer_reset_n = rst_n_240m_tx;
	assign serializer_clock = clk_240m_tx;
	
	// Deserializer control signals
	assign deserializer_enable = rx_en && !iso_en;
	assign deserializer_reset_n = rst_n_240m_rx;
	assign deserializer_clock = clk_240m_rx;
	
	// Connect phy_ready status output
	// Other outputs (tx_active, tx_error, rx_active, rx_error) are already connected in PCS module
	
	// Physical Coding Sublayer
	serdesphy_pcs u_pcs (
		// Clock and Reset
		.clk_ref_24m        (clk_ref_24m),
		.rst_n              (rst_n),
		.phy_en             (phy_en),
		.iso_en             (iso_en),

		// Power On Reset
		.dvdd_ok(dvdd_ok),
		.avdd_ok(avdd_ok),
		
		// Clock domains
		.clk_240m_tx        (clk_240m_tx),
		.clk_240m_rx        (clk_240m_rx),
		// Clock domains reset
		.rst_n_24m          (rst_n_24m),
		.rst_n_240m_tx      (rst_n_240m_tx),
		.rst_n_240m_rx      (rst_n_240m_rx),
		
		// Clock enables
		.clk_24m_en         (clk_24m_en),
		.clk_240m_tx_en     (clk_240m_tx_en),
		.clk_240m_rx_en     (clk_240m_rx_en),
		
		// CSR Interface - I2C
		.sda                (sda),
		.scl                (scl),
		
		// CSR Interface - TX Controls
		.tx_en              (tx_en),
		.tx_fifo_en         (tx_fifo_en),
		.tx_prbs_en         (tx_prbs_en),
		.tx_idle            (tx_idle),
		.tx_data_sel        (tx_data_sel),
		
		// CSR Interface - RX Controls
		.rx_en              (rx_en),
		.rx_fifo_en         (rx_fifo_en),
		.rx_prbs_chk_en     (rx_prbs_chk_en),
		.rx_align_rst       (rx_align_rst),
		.rx_data_sel        (rx_data_sel),
		
		// CSR Interface - PLL Controls
		.vco_trim           (vco_trim),
		.cp_current         (cp_current),
		.pll_rst            (pll_rst),
		.pll_bypass         (pll_bypass),
		
		// CSR Interface - CDR Controls
		.cdr_gain           (cdr_gain),
		.cdr_fast_lock      (cdr_fast_lock),
		.cdr_rst            (cdr_rst),
		
		// CSR Interface - Debug
		.dbg_vctrl          (dbg_vctrl),
		.dbg_pd             (dbg_pd),
		.dbg_fifo           (dbg_fifo),
		
		// TX Data Interface
		.tx_data            (tx_data),
		.tx_valid           (tx_valid),
		
		// TX Serial Interface to PMA
		.tx_serial_data     (tx_serial_data),
		.tx_serial_valid    (tx_serial_valid),
		.tx_idle_pattern    (tx_idle_pattern),
		
		// RX Serial Interface from PMA
		.rx_serial_data     (rx_serial_data),
		.rx_serial_valid    (rx_serial_valid),
		.rx_serial_error    (rx_serial_error),
		
		// RX Data Interface
		.rx_data            (rx_data),
		.rx_valid           (rx_valid),
		
		// Power-on-Reset Status
		.power_good         (power_good),
		.por_active         (por_active),
		.por_complete       (por_complete),
		
		// PLL Status
		.pll_lock           (pll_lock),
		.pll_ready          (pll_ready),
		.pll_status         (pll_status),
		.pll_error          (pll_error),
		
		// PHY Ready Status
		.phy_ready          (phy_ready),
		
		// CDR Status
		.cdr_lock           (cdr_lock),
		
		// TX Status
		.tx_fifo_full       (tx_fifo_full),
		.tx_fifo_empty      (tx_fifo_empty),
		.tx_overflow        (tx_overflow),
		.tx_underflow       (tx_underflow),
		.tx_active          (tx_active),
		.tx_error           (tx_error),
		
		// RX Status
		.rx_fifo_full       (rx_fifo_full),
		.rx_fifo_empty      (rx_fifo_empty),
		.rx_overflow        (rx_overflow),
		.rx_underflow       (rx_underflow),
		.rx_active          (rx_active),
		.rx_error           (rx_error),
		.rx_aligned         (rx_aligned),
		
		// Serializer Interface Status (from PMA)
		.serializer_ready   (serializer_ready),
		.serializer_error   (serializer_error),
		.serializer_active  (serializer_active),
		.serializer_status  (serializer_status),
		
		// Deserializer Interface Status (from PMA)
		.deserializer_ready (deserializer_ready),
		.deserializer_lock  (deserializer_lock),
		.deserializer_error (deserializer_error),
		.deserializer_active(deserializer_active),
		.deserializer_status(deserializer_status),
		
		// PRBS Error
		.prbs_err           (prbs_err),
		
		// Debug Output
		.dbg_ana            (dbg_ana)
	);

	// Physical Medium Attachment
	serdesphy_pma u_pma (
		// Clock and Reset
		.clk_ref_24m        (clk_ref_24m),
		.rst_n              (rst_n),
		
		.clk_240m_tx        (clk_240m_tx),
		.clk_240m_rx        (clk_240m_rx),
		
		// Power Control
		.analog_iso_n       (analog_iso_n),
		.analog_reset_n     (analog_reset_n),
		
		// PLL Interface
		.pll_enable         (pll_enable),
		.pll_reset_n        (pll_reset_n),
		.pll_bypass_en      (pll_bypass_en),
		.pll_vco_trim       (vco_trim),
		.pll_cp_current     (cp_current),
		.pll_iso_n          (pll_iso_n),
		
		// PLL Status
		.pll_lock_raw       (pll_lock_raw),
		.pll_vco_ok         (pll_vco_ok),
		.pll_cp_ok          (pll_cp_ok),
		
		// TX Serializer Interface
		.serializer_enable  (serializer_enable),
		.serializer_clock   (serializer_clock),
		.serializer_reset_n (serializer_reset_n),
		.serializer_data    (tx_serial_data),
		.serializer_bypass  (test_mode),
		
		// Serializer Status
		.serializer_ready   (serializer_ready),
		.serializer_error   (serializer_error),
		.serializer_active  (serializer_active),
		.serializer_status  (serializer_status),
		
		// RX Deserializer Interface
		.deserializer_enable(deserializer_enable),
		.deserializer_clock (deserializer_clock),
		.deserializer_reset_n(deserializer_reset_n),
		.deserializer_bypass(test_mode),
		
		// Deserializer Status
		.deserializer_ready (deserializer_ready),
		.deserializer_lock  (deserializer_lock),
		.deserializer_error (deserializer_error),
		.deserializer_active(deserializer_active),
		.deserializer_status(deserializer_status),
		.deserializer_data  (deserializer_data),
		
		// Differential TX Outputs
		.txp                (txp),
		.txn                (txn),
		
		// Differential RX Inputs
		.rxp                (rxp),
		.rxn                (rxn),
		
		// Loopback Control
		.lpbk_en            (lpbk_en),
		
		// Debug Interface
		.dbg_ana            (dbg_ana)
	);

	
endmodule