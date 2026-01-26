//////////////////////////////////////////////////////////////////////
////                                                              ////
//// serdesphy_registerInterface.v                                ////
////                                                              ////
//// Based on OpenCore i2cSlave registerInterface                 ////
//// Modified for SerDes PHY CSR register bank                    ////
////                                                              ////
//// Module Description:                                          ////
//// 8-register bank for SerDes PHY configuration and status      ////
//// Registers 0x00-0x05, 0x07 are read-write                     ////
//// Register 0x06 is read-only (status)                          ////
////                                                              ////
//// Register Map:                                                ////
//// 0x00 - PHY_ENABLE:  PHY enable and isolation control         ////
//// 0x01 - TX_CONFIG:   TX enable, FIFO, PRBS, idle control      ////
//// 0x02 - RX_CONFIG:   RX enable, FIFO, PRBS check, align       ////
//// 0x03 - DATA_SELECT: TX/RX data path routing                  ////
//// 0x04 - PLL_CONFIG:  VCO trim, CP current, PLL control        ////
//// 0x05 - CDR_CONFIG:  CDR gain, fast lock, reset               ////
//// 0x06 - STATUS:      Read-only status (locks, FIFOs, errors)  ////
//// 0x07 - DEBUG_EN:    Debug output enables                     ////
////                                                              ////
//// Original Author: Steve Fielding, sfielding@base2designs.com  ////
//// Copyright (C) 2008 Steve Fielding and OPENCORES.ORG          ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//////////////////////////////////////////////////////////////////////

`default_nettype none
`timescale 1ns / 1ps

module serdesphy_registerInterface (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  addr,
    input  wire [7:0]  dataIn,
    input  wire        writeEn,
    output reg  [7:0]  dataOut,

    // Register outputs (directly accessible by CSR top)
    output reg  [7:0]  reg_phy_enable,    // 0x00
    output reg  [7:0]  reg_tx_config,     // 0x01
    output reg  [7:0]  reg_rx_config,     // 0x02
    output reg  [7:0]  reg_data_select,   // 0x03
    output reg  [7:0]  reg_pll_config,    // 0x04
    output reg  [7:0]  reg_cdr_config,    // 0x05
    input  wire [7:0]  reg_status,        // 0x06 (read-only, from external)
    output reg  [7:0]  reg_debug_enable,  // 0x07

    // Write strobe for external notification
    output reg         reg_write_strobe,
    output reg  [7:0]  reg_write_addr
);

    // I2C Read - multiplexed register output
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dataOut <= 8'h00;
        end else begin
            case (addr[2:0])  // Only use lower 3 bits for 8 registers
                3'h0: dataOut <= reg_phy_enable;
                3'h1: dataOut <= reg_tx_config;
                3'h2: dataOut <= reg_rx_config;
                3'h3: dataOut <= reg_data_select;
                3'h4: dataOut <= reg_pll_config;
                3'h5: dataOut <= reg_cdr_config;
                3'h6: dataOut <= reg_status;      // Read-only status
                3'h7: dataOut <= reg_debug_enable;
                default: dataOut <= 8'h00;
            endcase
        end
    end

    // I2C Write - register bank update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_phy_enable   <= 8'h02;
            reg_tx_config    <= 8'h00;
            reg_rx_config    <= 8'h00;
            reg_data_select  <= 8'h00;
            reg_pll_config   <= 8'h00;
            reg_cdr_config   <= 8'h00;
            reg_debug_enable <= 8'h00;
            reg_write_strobe <= 1'b0;
            reg_write_addr   <= 8'h00;
        end else begin
            reg_write_strobe <= 1'b0;  // Default: clear strobe

            if (writeEn == 1'b1) begin
                reg_write_strobe <= 1'b1;
                reg_write_addr   <= addr;

                case (addr[2:0])
                    3'h0: reg_phy_enable   <= {{6{1'b0}}, dataIn[1:0]};
                    3'h1: reg_tx_config    <= dataIn;
                    3'h2: reg_rx_config    <= dataIn;
                    3'h3: reg_data_select  <= dataIn;
                    3'h4: reg_pll_config   <= dataIn;
                    3'h5: reg_cdr_config   <= dataIn;
                    // 3'h6: Status register is read-only, writes ignored
                    3'h7: reg_debug_enable <= dataIn;
                    default: ;  // Ignore writes to undefined addresses
                endcase
            end
        end
    end

endmodule
