/*
 * SerDes PHY Deserializer Interface Module
 * Interface between analog deserializer and rx_top digital logic
 * Handles clock domain crossing, data synchronization, and deserializer control
 */

`default_nettype none

module serdesphy_deserializer_if (
    // Clock and reset
    input  wire       clk_24m,          // 24 MHz system clock
    input  wire       clk_240m_rx,      // 240 MHz RX clock (from CDR)
    input  wire       rst_n_24m,         // 24MHz domain reset
    input  wire       rst_n_240m_rx,     // 240MHz RX domain reset
    
    // Control inputs from CSR
    input  wire       rx_en,            // Receive enable
    input  wire       deserializer_bypass,// Deserializer bypass (test mode)
    
    // Analog deserializer interface
    input  wire       deserializer_data, // Serial data from analog deserializer
    output wire       deserializer_enable,// Deserializer enable
    output wire       deserializer_clock, // Deserializer clock reference
    output wire       deserializer_reset_n,// Deserializer reset (active-low)
    
    // Deserializer status from analog
    input  wire       deserializer_ready, // Deserializer ready flag
    input  wire       deserializer_lock,  // Deserializer lock status
    input  wire       deserializer_error, // Deserializer error flag
    
    // Digital interface to rx_top
    output wire       rx_serial_data,   // Serial data to rx_top
    output wire       rx_serial_valid,  // Serial data valid to rx_top
    output wire       rx_serial_error,  // Serial data error to rx_top
    
    // Status outputs to rx_top/CSR
    output wire       deserializer_active,// Deserializer active status
    output wire       deserializer_status,// Deserializer status
    output wire       if_error          // Interface error flag
);

    // Deserializer control state machine
    localparam [2:0]
        DESIF_STATE_DISABLED   = 3'b000,  // Deserializer disabled
        DESIF_STATE_RESET      = 3'b001,  // Reset deserializer
        DESIF_STATE_CONFIG     = 3'b010,  // Configure deserializer
        DESIF_STATE_STARTING   = 3'b011,  // Starting deserializer
        DESIF_STATE_ACQUIRE    = 3'b100,  // Acquire lock
        DESIF_STATE_ACTIVE     = 3'b101,  // Deserializer active
        DESIF_STATE_ERROR      = 3'b110;  // Error state
    
    // Internal signals
    reg [2:0]   desif_state;
    reg         deserializer_enable_reg;
    reg         deserializer_clock_reg;
    reg         deserializer_reset_n_reg;
    reg         deserializer_active_reg;
    reg         deserializer_status_reg;
    reg         if_error_reg;
    reg [2:0]   error_count;
    reg [7:0]   lock_counter;
    
    // Clock domain crossing registers
    reg         deserializer_data_24m;
    reg         deserializer_data_valid_24m;
    reg [2:0]   sync_stage;
    
    // Data validity tracking
    reg         last_data;
    reg         transition_detected;
    reg [7:0]   transition_counter;
    
    // Clock domain crossing for data signals (240MHz to 24MHz)
    always @(posedge clk_240m_rx or negedge rst_n_240m_rx) begin
        if (!rst_n_240m_rx) begin
            sync_stage <= 3'b000;
        end else begin
            // Detect data transitions for validity indication
            if (deserializer_data != last_data) begin
                transition_detected <= 1'b1;
                transition_counter <= transition_counter + 1;
            end else begin
                transition_detected <= 1'b0;
            end
            last_data <= deserializer_data;
        end
    end
    
    // Synchronize data to 24MHz domain
    always @(posedge clk_24m or negedge rst_n_24m) begin
        if (!rst_n_24m) begin
            sync_stage <= 3'b000;
            deserializer_data_24m <= 1'b0;
            deserializer_data_valid_24m <= 1'b0;
        end else begin
            // Multi-stage synchronizer for data
            sync_stage <= {sync_stage[1:0], deserializer_data};
            deserializer_data_24m <= sync_stage[2];
            
            // Generate valid pulse when data changes and deserializer is locked
            deserializer_data_valid_24m <= transition_detected && deserializer_lock && 
                                         deserializer_active_reg;
        end
    end
    
    // Deserializer state machine (24MHz domain)
    always @(posedge clk_24m or negedge rst_n_24m) begin
        if (!rst_n_24m) begin
            desif_state <= DESIF_STATE_DISABLED;
            deserializer_enable_reg <= 1'b0;
            deserializer_reset_n_reg <= 1'b1;  // No reset initially
            deserializer_active_reg <= 1'b0;
            deserializer_status_reg <= 1'b0;
            if_error_reg <= 1'b0;
            error_count <= 3'd0;
            lock_counter <= 8'd0;
        end else begin
            case (desif_state)
                DESIF_STATE_DISABLED: begin
                    deserializer_enable_reg <= 1'b0;
                    deserializer_reset_n_reg <= 1'b0;  // Assert reset
                    deserializer_active_reg <= 1'b0;
                    if (rx_en && !deserializer_bypass) begin
                        desif_state <= DESIF_STATE_RESET;
                    end
                end
                
                DESIF_STATE_RESET: begin
                    // Hold reset for a few cycles
                    if (lock_counter < 8'd10) begin
                        lock_counter <= lock_counter + 1;
                    end else begin
                        deserializer_reset_n_reg <= 1'b1;  // Release reset
                        desif_state <= DESIF_STATE_CONFIG;
                        lock_counter <= 8'd0;
                    end
                end
                
                DESIF_STATE_CONFIG: begin
                    deserializer_enable_reg <= 1'b1;
                    if (deserializer_ready) begin
                        desif_state <= DESIF_STATE_STARTING;
                    end
                end
                
                DESIF_STATE_STARTING: begin
                    // Wait for initial lock acquisition
                    if (deserializer_lock) begin
                        if (lock_counter < 8'd50) begin  // Debounce lock
                            lock_counter <= lock_counter + 1;
                        end else begin
                            deserializer_active_reg <= 1'b1;
                            desif_state <= DESIF_STATE_ACQUIRE;
                            lock_counter <= 8'd0;
                        end
                    end else begin
                        lock_counter <= 8'd0;
                    end
                end
                
                DESIF_STATE_ACQUIRE: begin
                    // Verify stable data reception
                    if (transition_counter >= 8'd100) begin  // Found sufficient transitions
                        desif_state <= DESIF_STATE_ACTIVE;
                        lock_counter <= 8'd0;
                    end else if (lock_counter < 8'd200) begin  // Timeout after 200 cycles
                        lock_counter <= lock_counter + 1;
                    end else begin
                        // Timeout - return to starting
                        desif_state <= DESIF_STATE_STARTING;
                        lock_counter <= 8'd0;
                    end
                end
                
                DESIF_STATE_ACTIVE: begin
                    if (!rx_en) begin
                        desif_state <= DESIF_STATE_DISABLED;
                    end else if (deserializer_error || !deserializer_ready || !deserializer_lock) begin
                        if (error_count < 3'd7) begin
                            error_count <= error_count + 1;
                        end else begin
                            desif_state <= DESIF_STATE_ERROR;
                            if_error_reg <= 1'b1;
                        end
                    end
                end
                
                DESIF_STATE_ERROR: begin
                    deserializer_active_reg <= 1'b0;
                    if (!rx_en) begin
                        desif_state <= DESIF_STATE_DISABLED;
                        if_error_reg <= 1'b0;
                        error_count <= 3'd0;
                    end
                end
                
                default: begin
                    desif_state <= DESIF_STATE_ERROR;
                    if_error_reg <= 1'b1;
                end
            endcase
        end
    end
    
    // Deserializer clock generation (24MHz reference)
    always @(posedge clk_24m or negedge rst_n_24m) begin
        if (!rst_n_24m) begin
            deserializer_clock_reg <= 1'b0;
        end else if (deserializer_enable_reg) begin
            deserializer_clock_reg <= !deserializer_clock_reg;  // Divide by 2 for 12MHz
        end else begin
            deserializer_clock_reg <= 1'b0;
        end
    end
    
    // Data error detection
    reg data_error_reg;
    always @(posedge clk_24m or negedge rst_n_24m) begin
        if (!rst_n_24m) begin
            data_error_reg <= 1'b0;
        end else begin
            // Error if we expect data but don't get transitions
            if (deserializer_active_reg && deserializer_lock && 
                transition_counter == 8'd0 && lock_counter > 8'd100) begin
                data_error_reg <= 1'b1;
            end else if (transition_counter > 8'd0) begin
                data_error_reg <= 1'b0;
            end
            
            // Increment lock counter in active state
            if (deserializer_active_reg) begin
                lock_counter <= lock_counter + 1;
            end else begin
                lock_counter <= 8'd0;
            end
        end
    end
    
    // Status monitoring
    always @(posedge clk_24m or negedge rst_n_24m) begin
        if (!rst_n_24m) begin
            deserializer_status_reg <= 1'b0;
        end else begin
            deserializer_status_reg <= deserializer_ready && 
                                      deserializer_lock && 
                                      !deserializer_error;
        end
    end
    
    // Output assignments
    assign deserializer_enable = deserializer_enable_reg;
    assign deserializer_clock = deserializer_clock_reg;
    assign deserializer_reset_n = deserializer_reset_n_reg;
    
    assign rx_serial_data = deserializer_bypass ? deserializer_data : deserializer_data_24m;
    assign rx_serial_valid = deserializer_bypass ? 1'b1 : deserializer_data_valid_24m;
    assign rx_serial_error = data_error_reg || deserializer_error;
    
    assign deserializer_active = deserializer_active_reg;
    assign deserializer_status = deserializer_status_reg;
    assign if_error = if_error_reg;

endmodule