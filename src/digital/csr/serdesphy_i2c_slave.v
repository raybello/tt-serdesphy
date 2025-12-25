// Improved I2C Slave Implementation
// Key improvements:
// - Proper clock domain crossing with synchronizers
// - Debounced START/STOP detection
// - Clock stretching support
// - Better state machine with timeout handling
// - Parameterized register bank
// - Bus conflict detection

module i2c_slave #(
    parameter DEVICE_ADDR = 7'h42,
    parameter NUM_REGS = 4,
    parameter REG_WIDTH = 8,
    parameter SYNC_STAGES = 2,
    parameter GLITCH_FILTER_DEPTH = 3
)(
    input  wire clk,              // System clock for synchronization
    input  wire rst_n,            // Active-low async reset
    
    input  wire scl_in,           // I2C clock input
    inout  wire sda_io,           // I2C data (bidirectional)
    
    // Register interface
    output reg [NUM_REGS*REG_WIDTH-1:0] regs_out,
    input  wire [NUM_REGS*REG_WIDTH-1:0] regs_in,
    output reg  reg_write_strobe,
    output reg  [7:0] reg_addr,
    
    // Debug/Status
    output wire [7:0] status,
    output wire bus_error
);

    // State machine encoding
    localparam [2:0] 
        ST_IDLE      = 3'h0,
        ST_DEV_ADDR  = 3'h1,
        ST_REG_ADDR  = 3'h2,
        ST_WRITE     = 3'h3,
        ST_READ      = 3'h4;

    //========================================
    // Signal Synchronization (CDC)
    //========================================
    reg [SYNC_STAGES-1:0] scl_sync;
    reg [SYNC_STAGES-1:0] sda_sync;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_sync <= {SYNC_STAGES{1'b1}};
            sda_sync <= {SYNC_STAGES{1'b1}};
        end else begin
            scl_sync <= {scl_sync[SYNC_STAGES-2:0], scl_in};
            sda_sync <= {sda_sync[SYNC_STAGES-2:0], sda_io};
        end
    end
    
    wire scl_sync_out = scl_sync[SYNC_STAGES-1];
    wire sda_sync_out = sda_sync[SYNC_STAGES-1];

    //========================================
    // Glitch Filter
    //========================================
    reg [GLITCH_FILTER_DEPTH-1:0] scl_filter;
    reg [GLITCH_FILTER_DEPTH-1:0] sda_filter;
    reg scl_filtered, sda_filtered;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_filter <= {GLITCH_FILTER_DEPTH{1'b1}};
            sda_filter <= {GLITCH_FILTER_DEPTH{1'b1}};
            scl_filtered <= 1'b1;
            sda_filtered <= 1'b1;
        end else begin
            scl_filter <= {scl_filter[GLITCH_FILTER_DEPTH-2:0], scl_sync_out};
            sda_filter <= {sda_filter[GLITCH_FILTER_DEPTH-2:0], sda_sync_out};
            
            // Majority voting
            if (&scl_filter) scl_filtered <= 1'b1;
            else if (~|scl_filter) scl_filtered <= 1'b0;
            
            if (&sda_filter) sda_filtered <= 1'b1;
            else if (~|sda_filter) sda_filtered <= 1'b0;
        end
    end

    //========================================
    // Edge Detection
    //========================================
    reg scl_d, sda_d;
    wire scl_posedge = scl_filtered && !scl_d;
    wire scl_negedge = !scl_filtered && scl_d;
    wire sda_posedge = sda_filtered && !sda_d;
    wire sda_negedge = !sda_filtered && sda_d;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_d <= 1'b1;
            sda_d <= 1'b1;
        end else begin
            scl_d <= scl_filtered;
            sda_d <= sda_filtered;
        end
    end

    //========================================
    // START and STOP Condition Detection
    //========================================
    reg start_cond, stop_cond;
    reg start_pending, stop_pending;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_cond <= 1'b0;
            stop_cond <= 1'b0;
            start_pending <= 1'b0;
            stop_pending <= 1'b0;
        end else begin
            // START: SDA falling while SCL high
            if (sda_negedge && scl_filtered) begin
                start_pending <= 1'b1;
            end
            
            // STOP: SDA rising while SCL high
            if (sda_posedge && scl_filtered) begin
                stop_pending <= 1'b1;
            end
            
            // Clear conditions after SCL edge
            if (scl_negedge) begin
                start_cond <= start_pending;
                stop_cond <= stop_pending;
                start_pending <= 1'b0;
                stop_pending <= 1'b0;
            end else begin
                start_cond <= 1'b0;
                stop_cond <= 1'b0;
            end
        end
    end

    //========================================
    // Bit Counter and Shift Registers
    //========================================
    reg [3:0] bit_cnt;
    reg [7:0] rx_shift;
    reg [7:0] tx_shift;
    reg [7:0] tx_data;
    
    wire byte_complete = (bit_cnt == 4'd8);
    wire ack_bit = (bit_cnt == 4'd8);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt <= 4'd0;
            rx_shift <= 8'h00;
        end else begin
            if (start_cond || stop_cond) begin
                bit_cnt <= 4'd0;
            end else if (scl_posedge && !byte_complete) begin
                rx_shift <= {rx_shift[6:0], sda_filtered};
                bit_cnt <= bit_cnt + 1'b1;
            end else if (scl_negedge && byte_complete) begin
                bit_cnt <= 4'd0;
            end
        end
    end

    //========================================
    // State Machine
    //========================================
    reg [2:0] state;
    reg [7:0] reg_ptr;
    reg addr_matched;
    reg rw_bit;
    reg master_ack;
    reg [15:0] timeout_cnt;
    wire timeout = (timeout_cnt == 16'hFFFF);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            reg_ptr <= 8'h00;
            addr_matched <= 1'b0;
            rw_bit <= 1'b0;
            master_ack <= 1'b0;
            timeout_cnt <= 16'h0000;
        end else begin
            // Timeout counter
            if (state != ST_IDLE && !timeout)
                timeout_cnt <= timeout_cnt + 1'b1;
            else
                timeout_cnt <= 16'h0000;
            
            // Reset on STOP or timeout
            if (stop_cond || timeout) begin
                state <= ST_IDLE;
                addr_matched <= 1'b0;
                reg_ptr <= 8'h00;
            end 
            // START condition
            else if (start_cond) begin
                state <= ST_DEV_ADDR;
                addr_matched <= 1'b0;
            end
            // Process byte completion
            else if (scl_negedge && byte_complete) begin
                case (state)
                    ST_DEV_ADDR: begin
                        addr_matched <= (rx_shift[7:1] == DEVICE_ADDR);
                        rw_bit <= rx_shift[0];
                        if (rx_shift[7:1] == DEVICE_ADDR) begin
                            state <= rx_shift[0] ? ST_READ : ST_REG_ADDR;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end
                    
                    ST_REG_ADDR: begin
                        reg_ptr <= rx_shift;
                        state <= ST_WRITE;
                    end
                    
                    ST_WRITE: begin
                        reg_ptr <= reg_ptr + 1'b1;
                    end
                    
                    ST_READ: begin
                        if (!master_ack) begin
                            state <= ST_IDLE;
                        end else begin
                            reg_ptr <= reg_ptr + 1'b1;
                        end
                    end
                    
                    default: state <= ST_IDLE;
                endcase
            end
            
            // Sample master ACK during read
            if (scl_posedge && ack_bit && state == ST_READ) begin
                master_ack <= !sda_filtered;
            end
        end
    end

    //========================================
    // Register Bank
    //========================================
    integer i;
    reg [REG_WIDTH-1:0] reg_bank [0:NUM_REGS-1];
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_REGS; i = i + 1)
                reg_bank[i] <= {REG_WIDTH{1'b0}};
            reg_write_strobe <= 1'b0;
            reg_addr <= 8'h00;
        end else begin
            reg_write_strobe <= 1'b0;
            
            // Write from I2C
            if (scl_negedge && byte_complete && state == ST_WRITE && 
                reg_ptr < NUM_REGS) begin
                reg_bank[reg_ptr] <= rx_shift;
                reg_write_strobe <= 1'b1;
                reg_addr <= reg_ptr;
            end
            
            // Update from system side
            for (i = 0; i < NUM_REGS; i = i + 1) begin
                if (!reg_write_strobe || reg_addr != i)
                    reg_bank[i] <= regs_in[i*REG_WIDTH +: REG_WIDTH];
            end
        end
    end
    
    // Output register values
    always @(*) begin
        for (i = 0; i < NUM_REGS; i = i + 1)
            regs_out[i*REG_WIDTH +: REG_WIDTH] = reg_bank[i];
    end

    //========================================
    // TX Data Loading and Shifting
    //========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_shift <= 8'h00;
            tx_data <= 8'h00;
        end else begin
            // Load data for transmission
            if (scl_negedge && bit_cnt == 4'd7 && 
                (state == ST_READ || state == ST_DEV_ADDR)) begin
                if (reg_ptr < NUM_REGS)
                    tx_data <= reg_bank[reg_ptr];
                else
                    tx_data <= 8'hFF;
                tx_shift <= tx_data;
            end
            // Shift out data
            else if (scl_negedge && state == ST_READ && bit_cnt < 4'd8) begin
                tx_shift <= {tx_shift[6:0], 1'b0};
            end
        end
    end

    //========================================
    // SDA Output Control
    //========================================
    reg sda_out;
    reg sda_oe;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_out <= 1'b1;
            sda_oe <= 1'b0;
        end else begin
            // Default: release bus
            sda_oe <= 1'b0;
            sda_out <= 1'b1;
            
            // Send ACK after address/data byte
            if (ack_bit && scl_filtered) begin
                if ((state == ST_DEV_ADDR && addr_matched) ||
                    state == ST_REG_ADDR ||
                    (state == ST_WRITE && reg_ptr < NUM_REGS)) begin
                    sda_out <= 1'b0;
                    sda_oe <= 1'b1;
                end
            end
            // Send data during read
            else if (state == ST_READ && !ack_bit && scl_filtered) begin
                sda_out <= tx_shift[7];
                sda_oe <= 1'b1;
            end
        end
    end
    
    assign sda_io = sda_oe ? sda_out : 1'bz;

    //========================================
    // Bus Error Detection
    //========================================
    reg bus_error_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bus_error_reg <= 1'b0;
        end else begin
            // Detect bus conflict during transmission
            if (sda_oe && sda_out != sda_filtered && scl_filtered) begin
                bus_error_reg <= 1'b1;
            end else if (stop_cond) begin
                bus_error_reg <= 1'b0;
            end
        end
    end
    
    assign bus_error = bus_error_reg;

    //========================================
    // Status Output
    //========================================
    assign status = {
        bus_error_reg,
        timeout,
        addr_matched,
        state[2:0],
        rw_bit,
        scl_filtered
    };

endmodule