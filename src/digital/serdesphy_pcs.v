/*
 * SerDes PHY Physical Coding Sublayer
 * The PCS acts as an interface between the PMA and the protocol controller,
and performs functions like data encoding and decoding and
descrambling etc. 
 */

 module serdesphy_pcs(
    // Clock and Reset
    input  wire       clk_ref_24m,        // 24 MHz reference clock
    input  wire       rst_n,              // Global reset (active-low)
    input  wire       phy_en,             // PHY enable
    input  wire       iso_en,             // Isolation enable
    
    // Power Monitoring (from top level)
    input  wire       dvdd_ok,            // 1.8V digital supply OK
    input  wire       avdd_ok,            // 3.3V analog supply OK
    
    // Clock domains
    input  wire       clk_240m_tx,        // 240 MHz TX clock (from PLL)
    input  wire       clk_240m_rx,        // 240 MHz RX clock (from CDR)
    input  wire       rst_n_24m,          // 24MHz domain reset
    input  wire       rst_n_240m_tx,      // 240MHz TX domain reset
    input  wire       rst_n_240m_rx,      // 240MHz RX domain reset
    
    // Clock enables
    input  wire       clk_24m_en,         // 24MHz clock enable
    input  wire       clk_240m_tx_en,     // 240MHz TX clock enable
    input  wire       clk_240m_rx_en,     // 240MHz RX clock enable
    
    // CSR Interface - I2C
    inout  wire       sda,                // I2C data
    input  wire       scl,                // I2C clock
    
    // CSR Interface - TX Controls
    input  wire       tx_en,              // Transmit enable
    input  wire       tx_fifo_en,         // TX FIFO enable
    input  wire       tx_prbs_en,         // TX PRBS enable
    input  wire       tx_idle,            // Force idle pattern
    input  wire       tx_data_sel,        // TX data source select (0=FIFO, 1=PRBS)
    
    // CSR Interface - RX Controls
    input  wire       rx_en,              // Receive enable
    input  wire       rx_fifo_en,         // RX FIFO enable
    input  wire       rx_prbs_chk_en,     // RX PRBS check enable
    input  wire       rx_align_rst,       // Reset alignment FSM
    input  wire       rx_data_sel,        // RX output select (0=FIFO, 1=PRBS status)
    
    // CSR Interface - PLL Controls
    input  wire [3:0] vco_trim,           // VCO trim control
    input  wire [1:0] cp_current,         // Charge pump current
    input  wire       pll_rst,            // PLL reset
    input  wire       pll_bypass,         // PLL bypass
    
    // CSR Interface - CDR Controls
    input  wire [2:0] cdr_gain,           // CDR loop gain
    input  wire       cdr_fast_lock,      // CDR fast lock enable
    input  wire       cdr_rst,            // CDR reset
    
    // CSR Interface - Debug
    input  wire       dbg_vctrl,          // Debug voltage control
    input  wire       dbg_pd,             // Debug power down
    input  wire       dbg_fifo,           // Debug FIFO control
    
    // TX Data Interface
    input  wire [3:0] tx_data,            // 4-bit transmit data
    input  wire       tx_valid,           // TX data valid strobe
    
    // TX Serial Interface to PMA
    output wire       tx_serial_data,     // Serial data to serializer
    output wire       tx_serial_valid,    // Serial data valid
    output wire       tx_idle_pattern,    // Idle pattern indicator
    
    // RX Serial Interface from PMA
    input  wire       rx_serial_data,     // Serial data from deserializer
    input  wire       rx_serial_valid,    // Serial data valid
    input  wire       rx_serial_error,    // Serial data error
    
    // RX Data Interface
    output wire [3:0] rx_data,            // 4-bit receive data
    output wire       rx_valid,           // RX data valid strobe
    
    // Power-on-Reset Status
    output wire       power_good,         // Power good indication
    output wire       por_active,         // Power-on-reset active
    output wire       por_complete,       // Power-on-reset complete
    
    // PLL Status
    output wire       pll_lock,           // PLL lock indication
    output wire       pll_ready,          // PLL ready indication
    output wire [7:0] pll_status,         // PLL status register
    output wire       pll_error,          // PLL error flag
    
    // CDR Status
    output wire       cdr_lock,           // CDR lock indication
    
    // TX Status
    output wire       tx_fifo_full,       // TX FIFO full flag
    output wire       tx_fifo_empty,      // TX FIFO empty flag
    output wire       tx_overflow,        // TX FIFO overflow (sticky)
    output wire       tx_underflow,       // TX FIFO underflow (sticky)
    output wire       tx_active,          // TX data path active
    output wire       tx_error,           // TX error flag
    
    // RX Status
    output wire       rx_fifo_full,       // RX FIFO full flag
    output wire       rx_fifo_empty,      // RX FIFO empty flag
    output wire       rx_overflow,        // RX FIFO overflow (sticky)
    output wire       rx_underflow,       // RX FIFO underflow (sticky)
    output wire       rx_active,          // RX data path active
    output wire       rx_error,           // RX error flag
    output wire       rx_aligned,         // RX alignment achieved
    
    // Serializer Interface Status (from PMA)
    input  wire       serializer_ready,   // Serializer ready flag
    input  wire       serializer_error,   // Serializer error flag
    input  wire       serializer_active,  // Serializer active status
    input  wire       serializer_status,  // Serializer status
    
    // Deserializer Interface Status (from PMA)
    input  wire       deserializer_ready, // Deserializer ready flag
    input  wire       deserializer_lock,  // Deserializer lock status
    input  wire       deserializer_error, // Deserializer error flag
    input  wire       deserializer_active,// Deserializer active status
    input  wire       deserializer_status,// Deserializer status
    
    // PRBS Error
    output wire       prbs_err,           // PRBS error indication
    
    // Debug Output
    output wire       dbg_ana,            // Debug analog control
    
    // Reset Control Outputs
    output wire       analog_iso_n,       // Analog isolation control (active-low)
    output wire       analog_reset_n      // Analog domain reset release
 );

    // Internal signals for reset synchronization
    wire digital_reset_n;

    // Power-on-Reset Controller
	serdesphy_por u_por (
		.dvdd_ok        (dvdd_ok),
		.avdd_ok        (avdd_ok),
		.rst_n_in       (rst_n),
		.clk            (clk_ref_24m),
		.phy_en         (phy_en),
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
		.phy_en          (phy_en),
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
	// serdesphy_tx_top u_tx (
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
	// serdesphy_rx_top u_rx (
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
	

 endmodule