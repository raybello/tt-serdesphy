/*
 * SerDes PHY Physical Coding Sublayer
 * The PCS acts as an interface between the PMA and the protocol controller,
and performs functions like data encoding and decoding and
descrambling etc. 
 */

 module serdesphy_pcs(
    // Clock and Reset
    input       clk_ref_24m,        // 24 MHz reference clock
    input       rst_n,              // Global reset (active-low)
    output      phy_en,             // PHY enable
    output      iso_en,             // Isolation enable
    
    // Power Monitoring (from top level)
    input       dvdd_ok,            // 1.8V digital supply OK
    input       avdd_ok,            // 3.3V analog supply OK
    
    // Clock domains
    input       clk_240m_tx,        // 240 MHz TX clock (from PLL)
    input       clk_240m_rx,        // 240 MHz RX clock (from CDR)

    output      rst_n_24m,          // 24MHz domain reset
    output      rst_n_240m_tx,      // 240MHz TX domain reset
    output      rst_n_240m_rx,      // 240MHz RX domain reset
    
    // Clock enables
    input       clk_24m_en,         // 24MHz clock enable
    input       clk_240m_tx_en,     // 240MHz TX clock enable
    input       clk_240m_rx_en,     // 240MHz RX clock enable
    
    // CSR Interface - I2C (separate signals for Tiny Tapeout IO)
    input       sda_in,             // I2C data input
    output      sda_out,            // I2C data output
    output      sda_oe,             // I2C data output enable
    input       scl,                // I2C clock
    
    // CSR Interface - TX Controls
    output      tx_en,              // Transmit enable
    output      tx_fifo_en,         // TX FIFO enable
    output      tx_prbs_en,         // TX PRBS enable
    output      tx_idle,            // Force idle pattern
    output      tx_data_sel,        // TX data source select (0=FIFO, 1=PRBS)
    
    // CSR Interface - RX Controls
    output      rx_en,              // Receive enable
    output      rx_fifo_en,         // RX FIFO enable
    output      rx_prbs_chk_en,     // RX PRBS check enable
    output      rx_align_rst,       // Reset alignment FSM
    output      rx_data_sel,        // RX output select (0=FIFO, 1=PRBS status)
    
    // CSR Interface - PLL Controls
    output [3:0] vco_trim,          // VCO trim control
    output [1:0] cp_current,        // Charge pump current
    output       pll_rst,           // PLL reset
    output       pll_bypass,        // PLL bypass
    
    // CSR Interface - CDR Controls
    output [2:0] cdr_gain,          // CDR loop gain
    output       cdr_fast_lock,     // CDR fast lock enable
    output       cdr_rst,           // CDR reset
    
    // CSR Interface - Debug
    output      dbg_vctrl,          // Debug voltage control
    output      dbg_pd,             // Debug power down
    output      dbg_fifo,           // Debug FIFO control
    
    // TX Data Interface
    input [3:0] tx_data,            // 4-bit transmit data
    input       tx_valid,           // TX data valid strobe
    
    // TX Serial Interface to PMA
    output       tx_serial_data,     // Serial data to serializer
    output       tx_serial_valid,    // Serial data valid
    output       tx_idle_pattern,    // Idle pattern indicator
    
    // RX Serial Interface from PMA
    input       rx_serial_data,     // Serial data from deserializer
    input       rx_serial_valid,    // Serial data valid
    input       rx_serial_error,    // Serial data error
    
    // RX Data Interface
    output [3:0] rx_data,            // 4-bit receive data
    output       rx_valid,           // RX data valid strobe
    
    // Power-on-Reset Status
    output       power_good,         // Power good indication
    output       por_active,         // Power-on-reset active
    output       por_complete,       // Power-on-reset complete
    
    // PLL Status
    output       pll_lock,           // PLL lock indication
    output       pll_ready,          // PLL ready indication
    output [7:0] pll_status,         // PLL status register
    output       pll_error,          // PLL error flag
    output       phy_ready,          // PHY ready flag
    
    // CDR Status
    output       cdr_lock,           // CDR lock indication
    
    // TX Status
    output       tx_fifo_full,       // TX FIFO full flag
    output       tx_fifo_empty,      // TX FIFO empty flag
    output       tx_overflow,        // TX FIFO overflow (sticky)
    output       tx_underflow,       // TX FIFO underflow (sticky)
    output       tx_active,          // TX data path active
    output       tx_error,           // TX error flag
    
    // RX Status
    output       rx_fifo_full,       // RX FIFO full flag
    output       rx_fifo_empty,      // RX FIFO empty flag
    output       rx_overflow,        // RX FIFO overflow (sticky)
    output       rx_underflow,       // RX FIFO underflow (sticky)
    output       rx_active,          // RX data path active
    output       rx_error,           // RX error flag
    output       rx_aligned,         // RX alignment achieved
    
    // Serializer Interface Status (from PMA)
    input       serializer_ready,   // Serializer ready flag
    input       serializer_error,   // Serializer error flag
    input       serializer_active,  // Serializer active status
    input       serializer_status,  // Serializer status
    
    // Deserializer Interface Status (from PMA)
    input       deserializer_ready, // Deserializer ready flag
    input       deserializer_lock,  // Deserializer lock status
    input       deserializer_error, // Deserializer error flag
    input       deserializer_active,// Deserializer active status
    input       deserializer_status,// Deserializer status
    
    // PRBS Error
    output wire       prbs_err,           // PRBS error indication
    
    // Debug Output
    output wire dbg_ana,            // Debug analog control
    
    // Reset Control Outputs
    output wire       analog_iso_n,       // Analog isolation control (active-low)
    output wire       analog_reset_n      // Analog domain reset release
 );

    // Internal signals for reset synchronization
    wire digital_reset_n;
	wire phy_en_r;

	assign phy_en = phy_en_r;

	// Internal wires for TX module outputs
	wire       tx_serial_data_int;
	wire       tx_serial_valid_int;
	wire       tx_idle_pattern_int;
	wire       tx_fifo_full_int;
	wire       tx_fifo_empty_int;
	wire       tx_overflow_int;
	wire       tx_underflow_int;
	wire       tx_active_int;
	wire       tx_error_int;

	// Internal wires for RX module outputs
	wire [3:0] rx_data_int;
	wire       rx_valid_int;
	wire       rx_fifo_full_int;
	wire       rx_fifo_empty_int;
	wire       rx_overflow_int;
	wire       rx_underflow_int;
	wire       rx_active_int;
	wire       rx_error_int;
	wire       rx_aligned_int;
	wire       prbs_err_int;

	// Connect internal wires to outputs
	assign tx_serial_data = tx_serial_data_int;
	assign tx_serial_valid = tx_serial_valid_int;
	assign tx_idle_pattern = tx_idle_pattern_int;
	assign tx_fifo_full = tx_fifo_full_int;
	assign tx_fifo_empty = tx_fifo_empty_int;
	assign tx_overflow = tx_overflow_int;
	assign tx_underflow = tx_underflow_int;
	assign tx_active = tx_active_int;
	assign tx_error = tx_error_int;

	assign rx_data = rx_data_int;
	assign rx_valid = rx_valid_int;
	assign rx_fifo_full = rx_fifo_full_int;
	assign rx_fifo_empty = rx_fifo_empty_int;
	assign rx_overflow = rx_overflow_int;
	assign rx_underflow = rx_underflow_int;
	assign rx_active = rx_active_int;
	assign rx_error = rx_error_int;
	assign rx_aligned = rx_aligned_int;
	assign prbs_err = prbs_err_int;

	// PLL/CDR lock status from serializer/deserializer status
	assign pll_lock = serializer_ready;
	assign cdr_lock = deserializer_lock;
	assign pll_ready = serializer_ready;
	assign phy_ready = power_good && digital_reset_n && serializer_ready;
	assign pll_status = {4'b0000, serializer_status, serializer_active, serializer_error, serializer_ready};
	assign pll_error = serializer_error;


    // Power-on-Reset Controller
	serdesphy_por u_por (
		.dvdd_ok        (dvdd_ok),
		.avdd_ok        (avdd_ok),
		.rst_n_in       (rst_n),
		.clk            (clk_ref_24m),
		.phy_en         (phy_en_r),
		.iso_en         (iso_en),
		.power_good     (power_good),
		.analog_iso_n   (analog_iso_n),
		.digital_reset_n(digital_reset_n),
		.analog_reset_n (analog_reset_n),
		.por_active     (por_active),
		.por_complete   (por_complete)
	);
	
	 // Reset Synchronizer
	 serdesphy_reset_synchronizer u_reset_sync (
		.clk_ref_24m     (clk_ref_24m),
		.rst_n_in        (digital_reset_n),
		.clk_240m_tx     (clk_240m_tx),
		.clk_240m_rx     (clk_240m_rx),
		.phy_en          (phy_en_r),
		.pll_rst         (pll_rst),
		.cdr_rst         (cdr_rst),
		.rst_n_24m       (rst_n_24m),
		.rst_n_240m_tx   (rst_n_240m_tx),
		.rst_n_240m_rx   (rst_n_240m_rx),
		.pll_rst_sync    (),
		.cdr_rst_sync    ()
	 );
	
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
	
	// CSR Top Module
	serdesphy_csr_top u_csr_top (
		.clk             (clk_ref_24m),
		.rst_n           (digital_reset_n),
		.sda_in          (sda_in),
		.sda_out         (sda_out),
		.sda_oe          (sda_oe),
		.scl             (scl),
		
		// Control outputs
		.phy_en          (phy_en_r),
		.iso_en          (iso_en),
		.tx_en           (tx_en),
		.tx_fifo_en      (tx_fifo_en),
		.tx_prbs_en      (tx_prbs_en),
		.tx_idle         (tx_idle),
		.rx_en           (rx_en),
		.rx_fifo_en      (rx_fifo_en),
		.rx_prbs_chk_en  (rx_prbs_chk_en),
		.rx_align_rst    (rx_align_rst),
		.tx_data_sel     (tx_data_sel),
		.rx_data_sel     (rx_data_sel),
		.vco_trim        (vco_trim),
		.cp_current      (cp_current),
		.pll_rst         (pll_rst),
		.pll_bypass      (pll_bypass),
		.cdr_gain        (cdr_gain),
		.cdr_fast_lock   (cdr_fast_lock),
		.cdr_rst         (cdr_rst),
		.dbg_vctrl       (dbg_vctrl),
		.dbg_pd          (dbg_pd),
		.dbg_fifo        (dbg_fifo),
		.dbg_an          (dbg_ana),
		
		// Status inputs (only the ones defined in CSR module)
		.tx_fifo_full    (tx_fifo_full),
		.tx_fifo_empty   (tx_fifo_empty),
		.tx_overflow     (tx_overflow),
		.tx_underflow    (tx_underflow),
		.rx_fifo_full    (rx_fifo_full),
		.rx_fifo_empty   (rx_fifo_empty),
		.rx_overflow     (rx_overflow),
		.rx_underflow    (rx_underflow),
		.pll_lock        (pll_lock),
		.cdr_lock        (cdr_lock),
		.prbs_err        (prbs_err)
	);
	
	
	// TX Top Module
	serdesphy_tx_top u_tx (
		.clk_24m          (clk_ref_24m),
		.clk_240m_tx      (clk_240m_tx),
		.rst_n_24m        (rst_n_24m),
		.rst_n_240m_tx    (rst_n_240m_tx),
		.tx_en            (tx_en),
		.tx_fifo_en       (tx_fifo_en),
		.tx_prbs_en       (tx_prbs_en),
		.tx_idle          (tx_idle),
		.tx_data_sel      (tx_data_sel),
		.tx_data          (tx_data),
		.tx_valid         (tx_valid),
		.tx_serial_data   (tx_serial_data_int),
		.tx_serial_valid  (tx_serial_valid_int),
		.tx_idle_pattern  (tx_idle_pattern_int),
		.tx_fifo_full     (tx_fifo_full_int),
		.tx_fifo_empty    (tx_fifo_empty_int),
		.tx_overflow      (tx_overflow_int),
		.tx_underflow     (tx_underflow_int),
		.tx_active        (tx_active_int),
		.tx_error         (tx_error_int),
		.clk_240m_tx_en   (clk_240m_tx_en)
	);
	
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

    // RX Top Module
	serdesphy_rx_top u_rx (
		.clk_24m          (clk_ref_24m),
		.clk_240m_rx      (clk_240m_rx),
		.rst_n_24m        (rst_n_24m),
		.rst_n_240m_rx    (rst_n_240m_rx),
		.rx_en            (rx_en),
		.rx_fifo_en       (rx_fifo_en),
		.rx_prbs_chk_en   (rx_prbs_chk_en),
		.rx_align_rst     (rx_align_rst),
		.rx_data_sel      (rx_data_sel),
		.rx_serial_data   (rx_serial_data),
		.rx_serial_valid  (rx_serial_valid),
		.rx_serial_error  (rx_serial_error),
		.rx_data          (rx_data_int),
		.rx_valid         (rx_valid_int),
		.rx_fifo_full     (rx_fifo_full_int),
		.rx_fifo_empty    (rx_fifo_empty_int),
		.rx_overflow      (rx_overflow_int),
		.rx_underflow     (rx_underflow_int),
		.rx_active        (rx_active_int),
		.rx_error         (rx_error_int),
		.rx_aligned       (rx_aligned_int),
		.prbs_err         (prbs_err_int),
		.clk_240m_rx_en   (clk_240m_rx_en)
	);
	
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
	

 endmodule