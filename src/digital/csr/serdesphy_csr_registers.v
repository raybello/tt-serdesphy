/*
 * SerDes PHY CSR Registers
 * Configuration and status registers accessible via I²C
 * Implements register map from README specification
 */

`default_nettype none

module serdesphy_csr_registers (
    // Clock and reset
    input  wire       clk,             // System clock
    input  wire       rst_n,           // Active-low reset
    
    // Register interface from I2C slave
    input  wire [7:0] reg_addr,        // Register address
    input  wire [7:0] reg_wdata,       // Register write data
    input  wire       reg_write_en,     // Register write enable
    output wire [7:0] reg_rdata,       // Register read data
    input  wire       reg_read_en,      // Register read enable
    
    // PHY control outputs
    output wire       phy_en,          // PHY global enable
    output wire       iso_en,          // Analog isolation enable
    output wire       tx_en,           // Transmit enable
    output wire       tx_fifo_en,      // TX FIFO enable
    output wire       tx_prbs_en,      // TX PRBS enable
    output wire       tx_idle,         // Force idle pattern
    output wire       rx_en,           // Receive enable
    output wire       rx_fifo_en,      // RX FIFO enable
    output wire       rx_prbs_chk_en,   // RX PRBS check enable
    output wire       rx_align_rst,     // Reset alignment FSM
    output wire       tx_data_sel,     // TX data source select
    output wire       rx_data_sel,     // RX output select
    output wire [3:0] vco_trim,        // VCO frequency trim
    output wire [1:0] cp_current,      // Charge pump current
    output wire       pll_rst,         // PLL reset
    output wire       pll_bypass,       // PLL bypass
    output wire [2:0] cdr_gain,        // CDR gain setting
    output wire       cdr_fast_lock,    // CDR fast lock mode
    output wire       cdr_rst,         // CDR reset
    output wire       dbg_vctrl,        // Debug VCO control voltage
    output wire       dbg_pd,           // Debug phase detector
    output wire       dbg_fifo,         // Debug FIFO status
    
    // PHY status inputs
    input  wire       pll_lock,        // PLL lock indicator
    input  wire       cdr_lock,        // CDR lock indicator
    input  wire       tx_fifo_full,    // TX FIFO full flag
    input  wire       tx_fifo_empty,   // TX FIFO empty flag
    input  wire       rx_fifo_full,    // RX FIFO full flag
    input  wire       rx_fifo_empty,   // RX FIFO empty flag
    input  wire       prbs_err,        // PRBS error flag
    input  wire       fifo_err         // FIFO error flag
);

    // Register addresses
    localparam ADDR_PHY_ENABLE   = 8'h00;
    localparam ADDR_TX_CONFIG    = 8'h01;
    localparam ADDR_RX_CONFIG    = 8'h02;
    localparam ADDR_DATA_SELECT  = 8'h03;
    localparam ADDR_PLL_CONFIG   = 8'h04;
    localparam ADDR_CDR_CONFIG   = 8'h05;
    localparam ADDR_STATUS       = 8'h06;
    localparam ADDR_DEBUG_ENABLE = 8'h07;
    
    // Register storage
    reg [7:0] phy_enable_reg;
    reg [7:0] tx_config_reg;
    reg [7:0] rx_config_reg;
    reg [7:0] data_select_reg;
    reg [7:0] pll_config_reg;
    reg [7:0] cdr_config_reg;
    reg [7:0] debug_enable_reg;
    
    // Status register (read-only, constructed from inputs)
    wire [7:0] status_reg;
    
    // Read data multiplexer
    reg [7:0] read_data_reg;
    
    // Initialize registers
    initial begin
        phy_enable_reg   = 8'h01;  // PHY enabled by default
        tx_config_reg    = 8'h00;  // TX disabled by default
        rx_config_reg    = 8'h00;  // RX disabled by default
        data_select_reg  = 8'h01;  // TX=PRBS, RX=FIFO
        pll_config_reg   = 8'h88;  // VCO trim=0x8, CP=0x2, PLL_RST=1
        cdr_config_reg   = 8'h14;  // CDR_GAIN=0x4, CDR_RST=1
        debug_enable_reg = 8'h00;  // Debug disabled
    end
    
    // Register write logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phy_enable_reg   <= 8'h01;
            tx_config_reg    <= 8'h00;
            rx_config_reg    <= 8'h00;
            data_select_reg  <= 8'h01;
            pll_config_reg   <= 8'h88;
            cdr_config_reg   <= 8'h14;
            debug_enable_reg <= 8'h00;
        end else if (reg_write_en) begin
            case (reg_addr)
                ADDR_PHY_ENABLE:   phy_enable_reg   <= reg_wdata;
                ADDR_TX_CONFIG:    tx_config_reg    <= reg_wdata;
                ADDR_RX_CONFIG:    rx_config_reg    <= reg_wdata;
                ADDR_DATA_SELECT:  data_select_reg  <= reg_wdata;
                ADDR_PLL_CONFIG:   pll_config_reg   <= reg_wdata;
                ADDR_CDR_CONFIG:   cdr_config_reg   <= reg_wdata;
                ADDR_DEBUG_ENABLE: debug_enable_reg <= reg_wdata;
                // STATUS is read-only
                default: ;  // Invalid address, ignore write
            endcase
        end
    end
    
    // Register read logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_data_reg <= 8'h00;
        end else if (reg_read_en) begin
            case (reg_addr)
                ADDR_PHY_ENABLE:   read_data_reg <= phy_enable_reg;
                ADDR_TX_CONFIG:    read_data_reg <= tx_config_reg;
                ADDR_RX_CONFIG:    read_data_reg <= rx_config_reg;
                ADDR_DATA_SELECT:  read_data_reg <= data_select_reg;
                ADDR_PLL_CONFIG:   read_data_reg <= pll_config_reg;
                ADDR_CDR_CONFIG:   read_data_reg <= cdr_config_reg;
                ADDR_STATUS:       read_data_reg <= status_reg;
                ADDR_DEBUG_ENABLE: read_data_reg <= debug_enable_reg;
                default:           read_data_reg <= 8'h00;  // Invalid address
            endcase
        end
    end
    
    // Status register construction
    assign status_reg = {
        fifo_err,        // Bit 7: FIFO overflow/underflow
        prbs_err,        // Bit 6: PRBS error detected
        rx_fifo_empty,   // Bit 5: RX FIFO empty flag
        rx_fifo_full,    // Bit 4: RX FIFO full flag
        tx_fifo_empty,   // Bit 3: TX FIFO empty flag
        tx_fifo_full,    // Bit 2: TX FIFO full flag
        cdr_lock,        // Bit 1: CDR phase lock indicator
        pll_lock         // Bit 0: PLL frequency lock indicator
    };
    
    // Control signal assignments
    assign phy_en         = phy_enable_reg[0];
    assign iso_en         = phy_enable_reg[1];
    assign tx_en          = tx_config_reg[0];
    assign tx_fifo_en     = tx_config_reg[1];
    assign tx_prbs_en     = tx_config_reg[2];
    assign tx_idle        = tx_config_reg[3];
    assign rx_en          = rx_config_reg[0];
    assign rx_fifo_en     = rx_config_reg[1];
    assign rx_prbs_chk_en = rx_config_reg[2];
    assign rx_align_rst   = rx_config_reg[3];
    assign tx_data_sel    = data_select_reg[0];
    assign rx_data_sel    = data_select_reg[1];
    assign vco_trim       = pll_config_reg[3:0];
    assign cp_current     = pll_config_reg[5:4];
    assign pll_rst        = pll_config_reg[6];
    assign pll_bypass     = pll_config_reg[7];
    assign cdr_gain       = cdr_config_reg[2:0];
    assign cdr_fast_lock  = cdr_config_reg[3];
    assign cdr_rst        = cdr_config_reg[4];
    assign dbg_vctrl      = debug_enable_reg[0];
    assign dbg_pd         = debug_enable_reg[1];
    assign dbg_fifo       = debug_enable_reg[2];
    
    // Register read data
    assign reg_rdata = read_data_reg;

endmodule