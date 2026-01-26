`default_nettype none
`timescale 1ns / 1ps

// Simple testbench for I2C slave module standalone validation
module tb_i2c_slave;

    // Clock and reset
    reg clk;
    reg rst_n;

    // I2C signals
    reg scl;
    reg sda_master;          // Master SDA drive
    reg sda_master_oe;       // Master SDA output enable
    wire sda_out;            // Slave SDA output
    wire sda_oe;             // Slave SDA output enable
    wire sda_line;           // Combined open-drain bus

    // Register outputs
    wire [7:0] reg_phy_enable;
    wire [7:0] reg_tx_config;
    wire [7:0] reg_rx_config;
    wire [7:0] reg_data_select;
    wire [7:0] reg_pll_config;
    wire [7:0] reg_cdr_config;
    wire [7:0] reg_debug_enable;
    wire reg_write_strobe;
    wire [7:0] reg_write_addr;

    // Status input (hardcoded for test)
    wire [7:0] reg_status = 8'hAA;

    // Open-drain bus modeling
    wire sda_master_drive = (sda_master_oe) ? sda_master : 1'b1;
    wire sda_slave_drive = (sda_oe) ? sda_out : 1'b1;
    assign sda_line = sda_master_drive & sda_slave_drive;

    // Clock generation (24 MHz)
    initial begin
        clk = 0;
        forever #21 clk = ~clk;
    end

    // DUT instantiation
    serdesphy_i2c_slave u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .sda_in           (sda_line),
        .sda_out          (sda_out),
        .sda_oe           (sda_oe),
        .scl              (scl),
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

    // I2C timing parameters
    localparam SCL_PERIOD = 2500;      // 400 kHz
    localparam SCL_HIGH = 1000;
    localparam SCL_LOW = 1500;
    localparam SETUP_TIME = 600;
    localparam HOLD_TIME = 600;

    // I2C slave address
    localparam I2C_ADDR = 7'h42;

    // Test results
    integer errors = 0;

    // Dump waveforms
    initial begin
        $dumpfile("tb_i2c_slave.fst");
        $dumpvars(0, tb_i2c_slave);
    end

    // I2C Tasks
    task i2c_start;
        begin
            sda_master_oe = 1;
            sda_master = 1;
            scl = 1;
            #SETUP_TIME;
            sda_master = 0;
            #HOLD_TIME;
            scl = 0;
            #SCL_LOW;
        end
    endtask

    task i2c_stop;
        begin
            sda_master_oe = 1;
            sda_master = 0;
            #SCL_LOW;
            scl = 1;
            #HOLD_TIME;
            sda_master = 1;
            #SETUP_TIME;
            sda_master_oe = 0;
        end
    endtask

    task i2c_write_byte;
        input [7:0] data;
        output ack;
        integer i;
        begin
            sda_master_oe = 1;
            for (i = 7; i >= 0; i = i - 1) begin
                sda_master = data[i];
                #(SCL_LOW/2);
                scl = 1;
                #SCL_HIGH;
                scl = 0;
                #(SCL_LOW/2);
            end
            // Release SDA for ACK
            sda_master_oe = 0;
            #(SCL_LOW/2);
            scl = 1;
            #(SCL_HIGH/2);
            ack = ~sda_line;  // ACK = 0 = success
            #(SCL_HIGH/2);
            scl = 0;
            #SCL_LOW;
        end
    endtask

    task i2c_read_byte;
        output [7:0] data;
        input send_ack;
        integer i;
        begin
            sda_master_oe = 0;  // Release SDA for slave to drive
            data = 8'h00;
            for (i = 7; i >= 0; i = i - 1) begin
                #(SCL_LOW/2);
                scl = 1;
                #(SCL_HIGH/2);
                data[i] = sda_line;
                #(SCL_HIGH/2);
                scl = 0;
                #(SCL_LOW/2);
            end
            // Send ACK/NACK
            sda_master_oe = 1;
            sda_master = send_ack ? 0 : 1;
            #(SCL_LOW/2);
            scl = 1;
            #SCL_HIGH;
            scl = 0;
            #SCL_LOW;
            sda_master_oe = 0;
        end
    endtask

    // High-level I2C operations
    task i2c_write_reg;
        input [7:0] reg_addr;
        input [7:0] data;
        reg ack;
        begin
            $display("I2C Write: Reg[0x%02X] = 0x%02X", reg_addr, data);
            i2c_start();
            i2c_write_byte({I2C_ADDR, 1'b0}, ack);
            if (!ack) $display("  ERROR: No ACK on address");
            i2c_write_byte(reg_addr, ack);
            if (!ack) $display("  ERROR: No ACK on reg addr");
            i2c_write_byte(data, ack);
            if (!ack) $display("  ERROR: No ACK on data");
            i2c_stop();
            #1000;
        end
    endtask

    task i2c_read_reg;
        input [7:0] reg_addr;
        output [7:0] data;
        reg ack;
        begin
            // Write phase - set register address
            i2c_start();
            i2c_write_byte({I2C_ADDR, 1'b0}, ack);
            if (!ack) $display("  ERROR: No ACK on address (write phase)");
            i2c_write_byte(reg_addr, ack);
            if (!ack) $display("  ERROR: No ACK on reg addr");
            // Repeated START - read phase
            i2c_start();
            i2c_write_byte({I2C_ADDR, 1'b1}, ack);
            if (!ack) $display("  ERROR: No ACK on address (read phase)");
            i2c_read_byte(data, 0);  // NACK on last byte
            i2c_stop();
            $display("I2C Read: Reg[0x%02X] = 0x%02X", reg_addr, data);
            #1000;
        end
    endtask

    // Main test
    initial begin
        // Initialize
        rst_n = 0;
        scl = 1;
        sda_master = 1;
        sda_master_oe = 0;

        // Reset
        #1000;
        rst_n = 1;
        #5000;

        $display("\n=== I2C Slave Block-Level Test ===\n");

        // Test 1: Write and read back register 0
        $display("Test 1: Write 0x55 to Reg 0x00");
        i2c_write_reg(8'h00, 8'h55);
        #5000;

        // Read back
        begin
            reg [7:0] read_data;
            i2c_read_reg(8'h00, read_data);
            if (read_data == 8'h55) begin
                $display("  PASS: Read back 0x%02X", read_data);
            end else begin
                $display("  FAIL: Expected 0x55, got 0x%02X", read_data);
                errors = errors + 1;
            end
        end

        // Test 2: Write to multiple registers
        $display("\nTest 2: Write to multiple registers");
        i2c_write_reg(8'h00, 8'h11);
        i2c_write_reg(8'h01, 8'h22);
        i2c_write_reg(8'h02, 8'h33);
        i2c_write_reg(8'h03, 8'h44);
        #5000;

        // Read back all
        begin
            reg [7:0] rd0, rd1, rd2, rd3;
            i2c_read_reg(8'h00, rd0);
            i2c_read_reg(8'h01, rd1);
            i2c_read_reg(8'h02, rd2);
            i2c_read_reg(8'h03, rd3);

            if (rd0 == 8'h11 && rd1 == 8'h22 && rd2 == 8'h33 && rd3 == 8'h44) begin
                $display("  PASS: All registers match");
            end else begin
                $display("  FAIL: Mismatch - Reg0=0x%02X, Reg1=0x%02X, Reg2=0x%02X, Reg3=0x%02X",
                         rd0, rd1, rd2, rd3);
                errors = errors + 1;
            end
        end

        // Test 3: Read status register (read-only)
        $display("\nTest 3: Read status register (0x06)");
        begin
            reg [7:0] status;
            i2c_read_reg(8'h06, status);
            if (status == 8'hAA) begin
                $display("  PASS: Status = 0x%02X (expected 0xAA)", status);
            end else begin
                $display("  FAIL: Status = 0x%02X (expected 0xAA)", status);
                errors = errors + 1;
            end
        end

        // Summary
        #5000;
        $display("\n=== Test Summary ===");
        if (errors == 0) begin
            $display("All tests PASSED");
        end else begin
            $display("%0d test(s) FAILED", errors);
        end
        $display("");

        $finish;
    end

endmodule
