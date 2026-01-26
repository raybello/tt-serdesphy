//////////////////////////////////////////////////////////////////////
////                                                              ////
//// serdesphy_serialInterface.v                                  ////
////                                                              ////
//// Based on OpenCore i2cSlave serialInterface                   ////
//// Modified for SerDes PHY CSR interface                        ////
////                                                              ////
//// Module Description:                                          ////
//// Perform all serial to parallel, and parallel                 ////
//// to serial conversions. Perform device address matching       ////
//// Handle arbitrary length I2C reads terminated by NAK          ////
//// from host, and arbitrary length I2C writes terminated        ////
//// by STOP from host                                            ////
//// The second byte of a I2C write is always interpreted         ////
//// as a register address, and becomes the base register address ////
//// for all read and write transactions.                         ////
//// I2C WRITE: devAddr, regAddr, data[regAddr], data[regAddr+1]  ////
//// I2C READ:  data[regAddr], data[regAddr+1], ..... data[N]     ////
//// Note: when regAddr reaches 255 it will automatically wrap    ////
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

module serdesphy_serialInterface (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  dataIn,
    output reg  [7:0]  dataOut,
    output reg  [7:0]  regAddr,
    input  wire        scl,
    input  wire        sdaIn,
    output reg         sdaOut,
    input  wire [1:0]  startStopDetState,
    output reg         clearStartStopDet,
    output reg         writeEn
);

    // Diagram signals declarations
    reg [2:0] bitCnt, next_bitCnt;
    reg [7:0] rxData, next_rxData;
    reg [1:0] streamSt, next_streamSt;
    reg [7:0] txData, next_txData;

    // Next state signals
    reg next_sdaOut;
    reg next_writeEn;
    reg [7:0] next_dataOut;
    reg next_clearStartStopDet;
    reg [7:0] next_regAddr;

    // BINARY ENCODED state machine: SISt
    // State codes definitions:
    localparam [3:0]
        START              = 4'b0000,
        CHK_RD_WR          = 4'b0001,
        READ_RD_LOOP       = 4'b0010,
        READ_WT_HI         = 4'b0011,
        READ_CHK_LOOP_FIN  = 4'b0100,
        READ_WT_LO         = 4'b0101,
        READ_WT_ACK        = 4'b0110,
        WRITE_WT_LO        = 4'b0111,
        WRITE_WT_HI        = 4'b1000,
        WRITE_CHK_LOOP_FIN = 4'b1001,
        WRITE_LOOP_WT_LO   = 4'b1010,
        WRITE_ST_LOOP      = 4'b1011,
        WRITE_WT_LO2       = 4'b1100,
        WRITE_WT_HI2       = 4'b1101,
        WRITE_CLR_WR       = 4'b1110,
        WRITE_CLR_ST_STOP  = 4'b1111;

    reg [3:0] CurrState_SISt, NextState_SISt;

    // NextState logic (combinatorial)
    always @(*) begin
        NextState_SISt = CurrState_SISt;
        // Set default values for outputs and signals
        next_streamSt = streamSt;
        next_txData = txData;
        next_rxData = rxData;
        next_sdaOut = sdaOut;
        next_writeEn = writeEn;
        next_dataOut = dataOut;
        next_bitCnt = bitCnt;
        next_clearStartStopDet = clearStartStopDet;
        next_regAddr = regAddr;

        case (CurrState_SISt)
            START: begin
                next_streamSt = `STREAM_IDLE;
                next_txData = 8'h00;
                next_rxData = 8'h00;
                next_sdaOut = 1'b1;
                next_writeEn = 1'b0;
                next_dataOut = 8'h00;
                next_bitCnt = 3'b000;
                next_clearStartStopDet = 1'b0;
                NextState_SISt = CHK_RD_WR;
            end

            CHK_RD_WR: begin
                if (streamSt == `STREAM_READ) begin
                    NextState_SISt = READ_RD_LOOP;
                    next_txData = dataIn;
                    next_regAddr = regAddr + 1'b1;
                    next_bitCnt = 3'b001;
                end else begin
                    NextState_SISt = WRITE_WT_HI;
                    next_rxData = 8'h00;
                end
            end

            READ_RD_LOOP: begin
                if (scl == 1'b0) begin
                    NextState_SISt = READ_WT_HI;
                    next_sdaOut = txData[7];
                    next_txData = {txData[6:0], 1'b0};
                end
            end

            READ_WT_HI: begin
                if (scl == 1'b1) begin
                    NextState_SISt = READ_CHK_LOOP_FIN;
                end
            end

            READ_CHK_LOOP_FIN: begin
                if (bitCnt == 3'b000) begin
                    NextState_SISt = READ_WT_LO;
                end else begin
                    NextState_SISt = READ_RD_LOOP;
                    next_bitCnt = bitCnt + 1'b1;
                end
            end

            READ_WT_LO: begin
                if (scl == 1'b0) begin
                    NextState_SISt = READ_WT_ACK;
                    next_sdaOut = 1'b1;
                end
            end

            READ_WT_ACK: begin
                if (scl == 1'b1) begin
                    NextState_SISt = CHK_RD_WR;
                    if (sdaIn == `I2C_NAK)
                        next_streamSt = `STREAM_IDLE;
                end
            end

            WRITE_WT_LO: begin
                if ((scl == 1'b0) && (startStopDetState == `STOP_DET ||
                    (streamSt == `STREAM_IDLE && startStopDetState == `NULL_DET))) begin
                    NextState_SISt = WRITE_CLR_ST_STOP;
                    case (startStopDetState)
                        `NULL_DET: next_bitCnt = bitCnt + 1'b1;
                        `START_DET: begin
                            next_streamSt = `STREAM_IDLE;
                            next_rxData = 8'h00;
                        end
                        default: ;
                    endcase
                    next_streamSt = `STREAM_IDLE;
                    next_clearStartStopDet = 1'b1;
                end else if (scl == 1'b0) begin
                    NextState_SISt = WRITE_ST_LOOP;
                    case (startStopDetState)
                        `NULL_DET: next_bitCnt = bitCnt + 1'b1;
                        `START_DET: begin
                            next_streamSt = `STREAM_IDLE;
                            next_rxData = 8'h00;
                        end
                        default: ;
                    endcase
                end
            end

            WRITE_WT_HI: begin
                if (scl == 1'b1) begin
                    NextState_SISt = WRITE_WT_LO;
                    next_rxData = {rxData[6:0], sdaIn};
                    next_bitCnt = 3'b000;
                end
            end

            WRITE_CHK_LOOP_FIN: begin
                if (bitCnt == 3'b111) begin
                    NextState_SISt = WRITE_CLR_WR;
                    next_sdaOut = `I2C_ACK;
                    case (streamSt)
                        `STREAM_IDLE: begin
                            if (rxData[7:1] == `I2C_ADDRESS &&
                                startStopDetState == `START_DET) begin
                                if (rxData[0] == 1'b1)
                                    next_streamSt = `STREAM_READ;
                                else
                                    next_streamSt = `STREAM_WRITE_ADDR;
                            end else begin
                                next_sdaOut = `I2C_NAK;
                            end
                        end
                        `STREAM_WRITE_ADDR: begin
                            next_streamSt = `STREAM_WRITE_DATA;
                            next_regAddr = rxData;
                        end
                        `STREAM_WRITE_DATA: begin
                            next_dataOut = rxData;
                            next_writeEn = 1'b1;
                        end
                        default:
                            next_streamSt = streamSt;
                    endcase
                end else begin
                    NextState_SISt = WRITE_ST_LOOP;
                    next_bitCnt = bitCnt + 1'b1;
                end
            end

            WRITE_LOOP_WT_LO: begin
                if (scl == 1'b0) begin
                    NextState_SISt = WRITE_CHK_LOOP_FIN;
                end
            end

            WRITE_ST_LOOP: begin
                if (scl == 1'b1) begin
                    NextState_SISt = WRITE_LOOP_WT_LO;
                    next_rxData = {rxData[6:0], sdaIn};
                end
            end

            WRITE_WT_LO2: begin
                if (scl == 1'b0) begin
                    NextState_SISt = CHK_RD_WR;
                    next_sdaOut = 1'b1;
                end
            end

            WRITE_WT_HI2: begin
                next_clearStartStopDet = 1'b0;
                if (scl == 1'b1) begin
                    NextState_SISt = WRITE_WT_LO2;
                end
            end

            WRITE_CLR_WR: begin
                if (writeEn == 1'b1)
                    next_regAddr = regAddr + 1'b1;
                next_writeEn = 1'b0;
                next_clearStartStopDet = 1'b1;
                NextState_SISt = WRITE_WT_HI2;
            end

            WRITE_CLR_ST_STOP: begin
                next_clearStartStopDet = 1'b0;
                NextState_SISt = CHK_RD_WR;
            end
        endcase
    end

    // Current State Logic (sequential)
    always @(posedge clk) begin
        if (rst == 1'b1)
            CurrState_SISt <= START;
        else
            CurrState_SISt <= NextState_SISt;
    end

    // Registered outputs logic
    // NOTE: regAddr is NOT reset on START detection (rst) to preserve
    // the register pointer across repeated START conditions used in read transactions
    always @(posedge clk) begin
        if (rst == 1'b1) begin
            sdaOut <= 1'b1;
            writeEn <= 1'b0;
            dataOut <= 8'h00;
            clearStartStopDet <= 1'b0;
            // regAddr is NOT reset here - preserve across repeated START
            streamSt <= `STREAM_IDLE;
            txData <= 8'h00;
            rxData <= 8'h00;
            bitCnt <= 3'b000;
        end else begin
            sdaOut <= next_sdaOut;
            writeEn <= next_writeEn;
            dataOut <= next_dataOut;
            clearStartStopDet <= next_clearStartStopDet;
            regAddr <= next_regAddr;
            streamSt <= next_streamSt;
            txData <= next_txData;
            rxData <= next_rxData;
            bitCnt <= next_bitCnt;
        end
    end

endmodule
