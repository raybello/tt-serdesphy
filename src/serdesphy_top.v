
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
	output	dbg_ana
	);

	// Internal clocks
	wire clk_240m_tx;
	wire clk_240m_rx;
	wire rst_n_24m;
	wire rst_n_240m_tx;
	wire rst_n_240m_rx;
	
	// Power-on-Reset signals
	wire dvdd_ok;        // 1.8V digital supply OK (assume always OK for now)
	wire avdd_ok;        // 3.3V analog supply OK (assume always OK for now)
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
	wire phy_ready;
	
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
	wire tx_active;
	wire tx_error;
	wire serializer_active;
	wire serializer_status;
	wire if_error_tx;
	
	// RX Interface signals
	wire rx_serial_data;
	wire rx_serial_valid;
	wire rx_serial_error;
	wire rx_fifo_full;
	wire rx_fifo_empty;
	wire rx_overflow;
	wire rx_underflow;
	wire rx_active;
	wire rx_error;
	wire rx_aligned;
	wire deserializer_active;
	wire deserializer_status;
	wire if_error_rx;
	
	// Analog interface signals (simplified models)
	wire serializer_ready = 1'b1;
	wire serializer_error = 1'b0;
	wire deserializer_ready = 1'b1;
	wire deserializer_lock = 1'b1;
	wire deserializer_error = 1'b0;
	wire pll_lock_raw = 1'b1;
	wire pll_vco_ok = 1'b1;
	wire pll_cp_ok = 1'b1;
	
	// // Power-on-Reset Controller
	// serdesphy_por u_por (
	// 	.dvdd_ok        (dvdd_ok),
	// 	.avdd_ok        (avdd_ok),
	// 	.rst_n_in       (rst_n),
	// 	.clk            (clk_ref_24m),
	// 	.phy_en         (phy_en),
	// 	.iso_en         (iso_en),
	// 	.power_good     (power_good),
	// 	.analog_iso_n   (analog_iso_n),
	// 	.digital_reset_n(digital_reset_n),
	// 	.analog_reset_n (analog_reset_n),
	// 	.por_active     (por_active),
	// 	.por_complete   (por_complete)
	// );
	
	// // PLL Controller
	// serdesphy_pll_ctrl u_pll_ctrl (
	// 	.clk_ref_24m     (clk_ref_24m),
	// 	.rst_n           (digital_reset_n),
	// 	.phy_en          (phy_en),
	// 	.vco_trim        (vco_trim),
	// 	.cp_current      (cp_current),
	// 	.pll_rst         (pll_rst),
	// 	.pll_bypass      (pll_bypass),
	// 	.pll_enable      (),  // To analog PLL
	// 	.pll_reset_n     (),  // To analog PLL
	// 	.pll_bypass_en   (),  // To analog PLL
	// 	.pll_vco_trim    (),  // To analog PLL
	// 	.pll_cp_current  (),  // To analog PLL
	// 	.pll_iso_n       (),  // To analog PLL
	// 	.pll_lock_raw    (pll_lock_raw),
	// 	.pll_vco_ok      (pll_vco_ok),
	// 	.pll_cp_ok       (pll_cp_ok),
	// 	.pll_lock        (pll_lock),
	// 	.pll_ready       (pll_ready),
	// 	.pll_status      (pll_status),
	// 	.pll_error       (pll_error),
	// 	.clk_24m_en      (clk_24m_en),
	// 	.clk_240m_tx_en  (clk_240m_tx_en),
	// 	.clk_240m_rx_en  (clk_240m_rx_en),
	// 	.cdr_lock        (cdr_lock),
	// 	.phy_ready       (phy_ready)
	// );
	
	// // CSR Top Module
	// serdesphy_csr_top u_csr_top (
	// 	.clk             (clk_ref_24m),
	// 	.rst_n           (digital_reset_n),
	// 	.sda             (sda),
	// 	.scl             (scl),
	// 	.phy_en          (phy_en),
	// 	.iso_en          (iso_en),
	// 	.tx_en           (tx_en),
	// 	.tx_fifo_en      (tx_fifo_en),
	// 	.tx_prbs_en      (tx_prbs_en),
	// 	.tx_idle         (tx_idle),
	// 	.rx_en           (rx_en),
	// 	.rx_fifo_en      (rx_fifo_en),
	// 	.rx_prbs_chk_en  (rx_prbs_chk_en),
	// 	.rx_align_rst    (rx_align_rst),
	// 	.tx_data_sel     (tx_data_sel),
	// 	.rx_data_sel     (rx_data_sel),
	// 	.vco_trim        (vco_trim),
	// 	.cp_current      (cp_current),
	// 	.pll_rst         (pll_rst),
	// 	.pll_bypass      (pll_bypass),
	// 	.cdr_gain        (cdr_gain),
	// 	.cdr_fast_lock   (cdr_fast_lock),
	// 	.cdr_rst         (cdr_rst),
	// 	.dbg_vctrl       (dbg_vctrl),
	// 	.dbg_pd          (dbg_pd),
	// 	.dbg_fifo        (dbg_fifo),
	// 	.dbg_an          (dbg_ana),
	// 	.tx_fifo_full    (tx_fifo_full),
	// 	.tx_fifo_empty   (tx_fifo_empty),
	// 	.tx_overflow     (tx_overflow),
	// 	.tx_underflow    (tx_underflow),
	// 	.tx_active       (tx_active),
	// 	.tx_error        (tx_error),
	// 	.rx_fifo_full    (rx_fifo_full),
	// 	.rx_fifo_empty   (rx_fifo_empty),
	// 	.rx_overflow     (rx_overflow),
	// 	.rx_underflow    (rx_underflow),
	// 	.rx_active       (rx_active),
	// 	.rx_error        (rx_error),
	// 	.rx_aligned      (rx_aligned),
	// 	.pll_lock        (pll_lock),
	// 	.cdr_lock        (cdr_lock),
	// 	.pll_ready       (pll_ready),
	// 	.phy_ready       (phy_ready),
	// 	.power_good      (power_good),
	// 	.por_active      (por_active),
	// 	.por_complete    (por_complete),
	// 	.prbs_err        (prbs_err),
	// 	.pll_status      (pll_status),
	// 	.pll_error       (pll_error),
	// 	.csr_busy        (),
	// 	.csr_error       (),
	// 	.system_status    ()
	// );
	
	// // Reset Synchronizer
	// serdesphy_reset_synchronizer u_reset_sync (
	// 	.clk_ref_24m     (clk_ref_24m),
	// 	.rst_n_in        (digital_reset_n),
	// 	.clk_240m_tx     (clk_240m_tx),
	// 	.clk_240m_rx     (clk_240m_rx),
	// 	.phy_en          (phy_en),
	// 	.pll_rst         (pll_rst),
	// 	.cdr_rst         (cdr_rst),
	// 	.rst_n_24m       (rst_n_24m),
	// 	.rst_n_240m_tx   (rst_n_240m_tx),
	// 	.rst_n_240m_rx   (rst_n_240m_rx),
	// 	.pll_rst_sync    (),
	// 	.cdr_rst_sync    ()
	// );
	
	// // TX Top Module
	// serdesphy_tx_top u_tx_top (
	// 	.clk_24m          (clk_ref_24m),
	// 	.clk_240m_tx      (clk_240m_tx),
	// 	.rst_n_24m        (rst_n_24m),
	// 	.rst_n_240m_tx    (rst_n_240m_tx),
	// 	.tx_en            (tx_en),
	// 	.tx_fifo_en       (tx_fifo_en),
	// 	.tx_prbs_en       (tx_prbs_en),
	// 	.tx_idle          (tx_idle),
	// 	.tx_data_sel      (tx_data_sel),
	// 	.tx_data          (tx_data),
	// 	.tx_valid         (tx_valid),
	// 	.tx_serial_data   (tx_serial_data),
	// 	.tx_serial_valid  (tx_serial_valid),
	// 	.tx_idle_pattern  (tx_idle_pattern),
	// 	.tx_fifo_full     (tx_fifo_full),
	// 	.tx_fifo_empty    (tx_fifo_empty),
	// 	.tx_overflow      (tx_overflow),
	// 	.tx_underflow     (tx_underflow),
	// 	.tx_active        (tx_active),
	// 	.tx_error         (tx_error),
	// 	.clk_240m_tx_en   (clk_240m_tx_en)
	// );
	
	// // Serializer Interface
	// serdesphy_serializer_if u_serializer_if (
	// 	.clk_24m          (clk_ref_24m),
	// 	.clk_240m_tx      (clk_240m_tx),
	// 	.rst_n_24m        (rst_n_24m),
	// 	.rst_n_240m_tx    (rst_n_240m_tx),
	// 	.tx_en            (tx_en),
	// 	.serializer_bypass(test_mode),
	// 	.tx_serial_data   (tx_serial_data),
	// 	.tx_serial_valid  (tx_serial_valid),
	// 	.tx_idle_pattern  (tx_idle_pattern),
	// 	.serializer_data  (),  // To analog serializer
	// 	.serializer_enable(),  // To analog serializer
	// 	.serializer_clock (),  // To analog serializer
	// 	.serializer_reset_n(), // To analog serializer
	// 	.serializer_ready (serializer_ready),
	// 	.serializer_error (serializer_error),
	// 	.serializer_active(serializer_active),
	// 	.serializer_status(serializer_status),
	// 	.if_error         (if_error_tx)
	// );
	
	// // RX Top Module
	// serdesphy_rx_top u_rx_top (
	// 	.clk_24m          (clk_ref_24m),
	// 	.clk_240m_rx      (clk_240m_rx),
	// 	.rst_n_24m        (rst_n_24m),
	// 	.rst_n_240m_rx    (rst_n_240m_rx),
	// 	.rx_en            (rx_en),
	// 	.rx_fifo_en       (rx_fifo_en),
	// 	.rx_prbs_chk_en   (rx_prbs_chk_en),
	// 	.rx_align_rst     (rx_align_rst),
	// 	.rx_data_sel      (rx_data_sel),
	// 	.rx_serial_data   (rx_serial_data),
	// 	.rx_serial_valid  (rx_serial_valid),
	// 	.rx_serial_error  (rx_serial_error),
	// 	.rx_data          (rx_data),
	// 	.rx_valid         (rx_valid),
	// 	.rx_fifo_full     (rx_fifo_full),
	// 	.rx_fifo_empty    (rx_fifo_empty),
	// 	.rx_overflow      (rx_overflow),
	// 	.rx_underflow     (rx_underflow),
	// 	.rx_active        (rx_active),
	// 	.rx_error         (rx_error),
	// 	.rx_aligned       (rx_aligned),
	// 	.clk_240m_rx_en   (clk_240m_rx_en)
	// );
	
	// // Deserializer Interface
	// serdesphy_deserializer_if u_deserializer_if (
	// 	.clk_24m          (clk_ref_24m),
	// 	.clk_240m_rx      (clk_240m_rx),
	// 	.rst_n_24m        (rst_n_24m),
	// 	.rst_n_240m_rx    (rst_n_240m_rx),
	// 	.rx_en            (rx_en),
	// 	.deserializer_bypass(test_mode),
	// 	.deserializer_data(),  // From analog deserializer
	// 	.deserializer_enable(), // To analog deserializer
	// 	.deserializer_clock (), // To analog deserializer
	// 	.deserializer_reset_n(), // To analog deserializer
	// 	.deserializer_ready(deserializer_ready),
	// 	.deserializer_lock (deserializer_lock),
	// 	.deserializer_error(deserializer_error),
	// 	.rx_serial_data   (rx_serial_data),
	// 	.rx_serial_valid  (rx_serial_valid),
	// 	.rx_serial_error  (rx_serial_error),
	// 	.deserializer_active(deserializer_active),
	// 	.deserializer_status(deserializer_status),
	// 	.if_error         (if_error_rx)
	// );
	
	// // Legacy analog clock enable (for compatibility)
	// serdesphy_ana_clk_enable u_ana_clk_enable(
	// 	.clk  (clk_ref_24m),    
	// 	.CE   (pll_lock)
	// );
	
endmodule