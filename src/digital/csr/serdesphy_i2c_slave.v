/*
 * SerDes PHY I2C Slave Interface
 * I²C slave interface at address 0x42 (7-bit)
 * All registers are 8 bits wide with byte-level addressing
 */

`default_nettype none

module serdesphy_i2c_slave (
    // Clock and reset
    input  wire       clk,              // System clock
    input  wire       rst_n,            // Active-low reset
    
    // I2C physical interface
    inout  wire       sda,              // I2C data (open-drain)
    input  wire       scl,              // I2C clock
    
    // Register interface
    output wire [7:0] reg_addr,        // Register address
    output wire [7:0] reg_wdata,       // Register write data
    output wire       reg_write_en,     // Register write enable
    input  wire [7:0] reg_rdata,       // Register read data
    output wire       reg_read_en,      // Register read enable
    
    // Status
    output wire       i2c_busy,        // I2C transaction active
    output wire       i2c_error         // I2C protocol error
);

    // I2C slave address (0x42 = 7'h42)
    localparam SLAVE_ADDR = 7'h42;
    
    // Internal signals
    wire       sda_in;
    reg        sda_out;
    reg        sda_oe;
    
    // I2C bus signals
    reg [7:0]  shift_reg;        // 8-bit shift register
    reg [3:0]  bit_counter;      // Bit counter
    reg [1:0]  i2c_state;        // State machine
    reg        address_match;     // Address match flag
    reg        read_write;        // 0=write, 1=read
    reg        ack_sent;         // ACK sent flag
    reg        start_detected;    // START condition detected
    reg        stop_detected;     // STOP condition detected
    reg        busy_flag;        // I2C busy flag
    reg        error_flag;       // I2C error flag
    
    // State encoding
    localparam STATE_IDLE      = 2'b00;
    localparam STATE_ADDR_ACK   = 2'b01;
    localparam STATE_REG_ADDR   = 2'b10;
    localparam STATE_DATA      = 2'b11;
    
    // I2C pin control (open-drain)
    assign sda = (sda_oe) ? sda_out : 1'bz;
    assign sda_in = sda;
    
    // START condition detection (SCL high, SDA falling edge)
    reg sda_d1, scl_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_d1 <= 1'b1;
            scl_d1 <= 1'b1;
        end else begin
            sda_d1 <= sda_in;
            scl_d1 <= scl;
        end
    end
    
    // Detect START and STOP conditions
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_detected <= 0;
            stop_detected <= 0;
        end else begin
            // START: SCL=1, SDA: 1→0
            start_detected <= scl_d1 && sda_d1 && scl && !sda_in;
            
            // STOP: SCL=1, SDA: 0→1  
            stop_detected <= scl_d1 && !sda_d1 && scl && sda_in;
        end
    end
    
    // Main I2C state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i2c_state <= STATE_IDLE;
            shift_reg <= 8'h00;
            bit_counter <= 4'h0;
            address_match <= 0;
            read_write <= 0;
            sda_out <= 1'b1;
            sda_oe <= 1'b0;
            ack_sent <= 0;
            busy_flag <= 0;
            error_flag <= 0;
        end else begin
            case (i2c_state)
                STATE_IDLE: begin
                    busy_flag <= 0;
                    sda_oe <= 1'b0;  // Release SDA
                    
                    if (start_detected) begin
                        busy_flag <= 1;
                        bit_counter <= 4'h8;  // Expect 8 bits address
                        shift_reg <= 8'h00;
                        i2c_state <= STATE_ADDR_ACK;
                    end
                end
                
                STATE_ADDR_ACK: begin
                    // Shift in address bits on SCL falling edge
                    if (!scl && scl_d1) begin  // Falling edge
                        shift_reg <= {shift_reg[6:0], sda_in};
                        if (bit_counter > 0) begin
                            bit_counter <= bit_counter - 1;
                        end
                    end
                    
                    // Check address on 8th bit rising edge
                    if (bit_counter == 0 && scl && !scl_d1) begin
                        if (shift_reg[7:1] == SLAVE_ADDR) begin
                            address_match <= 1;
                            read_write <= shift_reg[0];
                            sda_out <= 1'b0;  // Send ACK
                            sda_oe <= 1'b1;
                            ack_sent <= 1;
                            bit_counter <= 4'h8;  // Expect 8 bits register address
                            shift_reg <= 8'h00;
                        end else begin
                            error_flag <= 1;
                            sda_oe <= 1'b0;  // Not addressed
                            i2c_state <= STATE_IDLE;
                        end
                    end
                    
                    // Release ACK after SCL high period
                    if (ack_sent && scl && scl_d1) begin
                        sda_oe <= 1'b0;
                        ack_sent <= 0;
                        i2c_state <= STATE_REG_ADDR;
                    end
                end
                
                STATE_REG_ADDR: begin
                    // Shift in register address
                    if (!scl && scl_d1) begin  // Falling edge
                        shift_reg <= {shift_reg[6:0], sda_in};
                        if (bit_counter > 0) begin
                            bit_counter <= bit_counter - 1;
                        end
                    end
                    
                    // Send ACK for register address
                    if (bit_counter == 0 && scl && !scl_d1) begin
                        sda_out <= 1'b0;  // Send ACK
                        sda_oe <= 1'b1;
                        ack_sent <= 1;
                        bit_counter <= 4'h8;
                    end
                    
                    // Move to data phase
                    if (ack_sent && scl && scl_d1) begin
                        sda_oe <= 1'b0;
                        ack_sent <= 0;
                        i2c_state <= STATE_DATA;
                    end
                end
                
                STATE_DATA: begin
                    if (read_write == 0) begin
                        // Write operation
                        if (!scl && scl_d1) begin  // Falling edge
                            shift_reg <= {shift_reg[6:0], sda_in};
                            if (bit_counter > 0) begin
                                bit_counter <= bit_counter - 1;
                            end
                        end
                        
                        // Send ACK for data byte
                        if (bit_counter == 0 && scl && !scl_d1) begin
                            sda_out <= 1'b0;  // Send ACK
                            sda_oe <= 1'b1;
                            ack_sent <= 1;
                            bit_counter <= 4'h8;
                        end
                        
                        if (ack_sent && scl && scl_d1) begin
                            sda_oe <= 1'b0;
                            ack_sent <= 0;
                        end
                    end else begin
                        // Read operation
                        if (scl && !scl_d1) begin  // Rising edge - master reads
                            shift_reg <= reg_rdata;
                            sda_out <= shift_reg[7];  // MSB first
                            sda_oe <= 1'b1;
                        end
                        
                        if (!scl && scl_d1) begin  // Falling edge
                            shift_reg <= shift_reg << 1;
                            sda_out <= shift_reg[7];
                            
                            if (bit_counter > 0) begin
                                bit_counter <= bit_counter - 1;
                            end
                        end
                        
                        // Release SDA for master ACK/NACK
                        if (bit_counter == 0) begin
                            sda_oe <= 1'b0;  // Release for ACK/NACK
                        end
                    end
                    
                    // Check for STOP condition
                    if (stop_detected) begin
                        i2c_state <= STATE_IDLE;
                    end
                end
                
                default: begin
                    i2c_state <= STATE_IDLE;
                end
            endcase
        end
    end
    
    // Register interface signals
    assign reg_addr = shift_reg;  // Last received register address
    assign reg_wdata = shift_reg; // Last received write data
    assign reg_write_en = (i2c_state == STATE_DATA) && (read_write == 0) && 
                         (bit_counter == 0) && ack_sent;
    assign reg_read_en = (i2c_state == STATE_DATA) && (read_write == 1);
    
    // Status outputs
    assign i2c_busy = busy_flag;
    assign i2c_error = error_flag;

endmodule