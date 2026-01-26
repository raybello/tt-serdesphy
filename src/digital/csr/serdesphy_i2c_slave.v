//////////////////////////////////////////////////////////////////////
////                                                              ////
//// serdesphy_i2c_slave.v                                        ////
////                                                              ////
//// Based on OpenCore i2cSlave implementation                    ////
//// Modified for SerDes PHY CSR interface                        ////
////                                                              ////
//// Module Description:                                          ////
//// Top-level I2C slave module with debouncing, start/stop       ////
//// detection, and integration with serial and register          ////
//// interfaces for SerDes PHY configuration.                     ////
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

`include "serdesphy_i2c_defines.v"

module serdesphy_i2c_slave (
    input  wire        clk,           // System clock (24 MHz)
    input  wire        rst_n,         // Active-low async reset

    // I2C interface - separate signals for Tiny Tapeout IO
    input  wire        sda_in,        // SDA input (directly from IO pad)
    output wire        sda_out,       // SDA output (directly to IO pad)
    output wire        sda_oe,        // SDA output enable (active high)
    input  wire        scl,           // I2C clock

    // Register interface outputs
    output wire [7:0]  reg_phy_enable,
    output wire [7:0]  reg_tx_config,
    output wire [7:0]  reg_rx_config,
    output wire [7:0]  reg_data_select,
    output wire [7:0]  reg_pll_config,
    output wire [7:0]  reg_cdr_config,
    input  wire [7:0]  reg_status,
    output wire [7:0]  reg_debug_enable,

    // Write notification
    output wire        reg_write_strobe,
    output wire [7:0]  reg_write_addr
);

    // Internal signals
    wire rst;  // Active-high reset for internal logic

    // Debounced signals
    reg sdaDeb;
    reg sclDeb;
    reg [`DEB_I2C_LEN-1:0] sdaPipe;
    reg [`DEB_I2C_LEN-1:0] sclPipe;

    // Delayed signals for sampling and start/stop detection
    reg [`SCL_DEL_LEN-1:0] sclDelayed;
    reg [`SDA_DEL_LEN-1:0] sdaDelayed;

    // Start/stop detection
    reg [1:0] startStopDetState;
    wire clearStartStopDet;
    reg startEdgeDet;

    // SDA control
    wire sdaOut;
    wire sdaIn;

    // Register interface signals
    wire [7:0] regAddr;
    wire [7:0] dataToRegIF;
    wire writeEn;
    wire [7:0] dataFromRegIF;

    // Reset synchronization
    reg [1:0] rstPipe;
    wire rstSyncToClk;

    // SDA separate signal handling for Tiny Tapeout IO
    // sda_out is always low when enabled (open-drain pull-down)
    // sda_oe is active when slave wants to drive low (ACK or data 0)
    assign sda_out = 1'b0;
    assign sda_oe = (sdaOut == 1'b0);
    assign sdaIn = sda_in;

    // Convert active-low reset to active-high for internal logic
    assign rst = ~rst_n;

    // Sync reset rising edge to clk
    always @(posedge clk) begin
        if (rst == 1'b1)
            rstPipe <= 2'b11;
        else
            rstPipe <= {rstPipe[0], 1'b0};
    end

    assign rstSyncToClk = rstPipe[1];

    // Debounce SDA and SCL
    always @(posedge clk) begin
        if (rstSyncToClk == 1'b1) begin
            sdaPipe <= {`DEB_I2C_LEN{1'b1}};
            sdaDeb <= 1'b1;
            sclPipe <= {`DEB_I2C_LEN{1'b1}};
            sclDeb <= 1'b1;
        end else begin
            sdaPipe <= {sdaPipe[`DEB_I2C_LEN-2:0], sdaIn};
            sclPipe <= {sclPipe[`DEB_I2C_LEN-2:0], scl};

            // SCL debouncing with hysteresis
            if (&sclPipe[`DEB_I2C_LEN-1:1] == 1'b1)
                sclDeb <= 1'b1;
            else if (|sclPipe[`DEB_I2C_LEN-1:1] == 1'b0)
                sclDeb <= 1'b0;

            // SDA debouncing with hysteresis
            if (&sdaPipe[`DEB_I2C_LEN-1:1] == 1'b1)
                sdaDeb <= 1'b1;
            else if (|sdaPipe[`DEB_I2C_LEN-1:1] == 1'b0)
                sdaDeb <= 1'b0;
        end
    end

    // Delay SCL and SDA
    // sclDelayed is used as a delayed sampling clock
    // sdaDelayed is only used for start/stop detection
    // Because sda hold time from scl falling is 0nS
    // sda must be delayed with respect to scl to avoid incorrect
    // detection of start/stop at scl falling edge.
    always @(posedge clk) begin
        if (rstSyncToClk == 1'b1) begin
            sclDelayed <= {`SCL_DEL_LEN{1'b1}};
            sdaDelayed <= {`SDA_DEL_LEN{1'b1}};
        end else begin
            sclDelayed <= {sclDelayed[`SCL_DEL_LEN-2:0], sclDeb};
            sdaDelayed <= {sdaDelayed[`SDA_DEL_LEN-2:0], sdaDeb};
        end
    end

    // Start/stop detection
    always @(posedge clk) begin
        if (rstSyncToClk == 1'b1) begin
            startStopDetState <= `NULL_DET;
            startEdgeDet <= 1'b0;
        end else begin
            // Detect start edge (SDA falling while SCL high)
            if (sclDeb == 1'b1 && sdaDelayed[`SDA_DEL_LEN-2] == 1'b0 && sdaDelayed[`SDA_DEL_LEN-1] == 1'b1)
                startEdgeDet <= 1'b1;
            else
                startEdgeDet <= 1'b0;

            // State machine for start/stop detection
            if (clearStartStopDet == 1'b1)
                startStopDetState <= `NULL_DET;
            else if (sclDeb == 1'b1) begin
                // STOP: SDA rising while SCL high
                if (sdaDelayed[`SDA_DEL_LEN-2] == 1'b1 && sdaDelayed[`SDA_DEL_LEN-1] == 1'b0)
                    startStopDetState <= `STOP_DET;
                // START: SDA falling while SCL high
                else if (sdaDelayed[`SDA_DEL_LEN-2] == 1'b0 && sdaDelayed[`SDA_DEL_LEN-1] == 1'b1)
                    startStopDetState <= `START_DET;
            end
        end
    end

    // Register Interface instantiation
    serdesphy_registerInterface u_registerInterface (
        .clk              (clk),
        .rst_n            (rst_n),
        .addr             (regAddr),
        .dataIn           (dataToRegIF),
        .writeEn          (writeEn),
        .dataOut          (dataFromRegIF),
        .reg_phy_enable   (reg_phy_enable),
        .reg_tx_config    (reg_tx_config),
        .reg_rx_config    (reg_rx_config),
        .reg_data_select  (reg_data_select),
        .reg_pll_config   (reg_pll_config),
        .reg_cdr_config   (reg_cdr_config),
        .reg_status       (reg_status),
        .reg_debug_enable (reg_debug_enable),
        .reg_write_strobe (reg_write_strobe),
        .reg_write_addr   (reg_write_addr)
    );

    // Serial Interface instantiation
    serdesphy_serialInterface u_serialInterface (
        .clk               (clk),
        .rst               (rstSyncToClk | startEdgeDet),
        .dataIn            (dataFromRegIF),
        .dataOut           (dataToRegIF),
        .writeEn           (writeEn),
        .regAddr           (regAddr),
        .scl               (sclDelayed[`SCL_DEL_LEN-1]),
        .sdaIn             (sdaDeb),
        .sdaOut            (sdaOut),
        .startStopDetState (startStopDetState),
        .clearStartStopDet (clearStartStopDet)
    );

endmodule
