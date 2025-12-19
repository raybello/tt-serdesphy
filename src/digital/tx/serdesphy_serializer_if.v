/*
 * SerDes PHY Serializer Interface Module
 * Interface between tx_top digital logic and analog serializer
 * Handles clock domain crossing, data alignment, and serializer control
 */

`default_nettype none

module serdesphy_serializer_if (
    // Clock and reset
    input  wire       clk_24m,          // 24 MHz system clock
    input  wire       clk_240m_tx,      // 240 MHz TX clock (from PLL)
    input  wire       rst_n_24m,         // 24MHz domain reset
    input  wire       rst_n_240m_tx,     // 240MHz TX domain reset
    
    // Control inputs from CSR
    input  wire       tx_en,            // Transmit enable
    input  wire       serializer_bypass,// Serializer bypass (test mode)
    
    // Digital interface from tx_top
    input  wire       tx_serial_data,   // Serial data from tx_top
    input  wire       tx_serial_valid,  // Serial data valid from tx_top
    input  wire       tx_idle_pattern,  // Idle pattern indicator
    
    // Analog serializer interface
    output wire       serializer_data,  // Data to analog serializer
    output wire       serializer_enable,// Serializer enable
    output wire       serializer_clock, // Serializer clock
    output wire       serializer_reset_n,// Serializer reset (active-low)
    
    // Serializer status from analog
    input  wire       serializer_ready, // Serializer ready flag
    input  wire       serializer_error, // Serializer error flag
    
    // Status outputs to tx_top/CSR
    output wire       serializer_active,// Serializer active status
    output wire       serializer_status,// Serializer status
    output wire       if_error          // Interface error flag
);

    // Serializer control state machine
    localparam [2:0]
        SERIF_STATE_DISABLED   = 3'b000,  // Serializer disabled
        SERIF_STATE_RESET      = 3'b001,  // Reset serializer
        SERIF_STATE_CONFIG     = 3'b010,  // Configure serializer
        SERIF_STATE_STARTING   = 3'b011,  // Starting serializer
        SERIF_STATE_ACTIVE     = 3'b100,  // Serializer active
        SERIF_STATE_STOPPING   = 3'b101,  // Stopping serializer
        SERIF_STATE_ERROR      = 3'b110;  // Error state
    
    // Internal signals
    reg [2:0]   serif_state;
    reg         serializer_data_reg;
    reg         serializer_enable_reg;
    reg         serializer_clock_reg;
    reg         serializer_reset_n_reg;
    reg         serializer_active_reg;
    reg         serializer_status_reg;
    reg         if_error_reg;
    reg [2:0]   error_count;
    
    // Clock domain crossing registers
    reg         tx_serial_data_240m;
    reg         tx_serial_valid_240m;
    reg         tx_idle_pattern_240m;
    reg [2:0]   sync_stage;
    
    // Clock divider for serializer control
    reg [1:0]   clock_divider;
    reg         clock_enable;
    
    // Clock domain crossing for control signals
    always @(posedge clk_240m_tx or negedge rst_n_240m_tx) begin
        if (!rst_n_240m_tx) begin
            sync_stage <= 3'b000;
            tx_serial_data_240m <= 1'b0;
            tx_serial_valid_240m <= 1'b0;
            tx_idle_pattern_240m <= 1'b0;
        end else begin
            // Multi-stage synchronizer for control signals
            sync_stage <= {sync_stage[1:0], tx_serial_valid};
            
            // Synchronize data when valid
            if (tx_serial_valid) begin
                tx_serial_data_240m <= tx_serial_data;
                tx_idle_pattern_240m <= tx_idle_pattern;
            end
            
            // Generate synchronized valid pulse
            tx_serial_valid_240m <= (sync_stage == 3'b011);
        end
    end
    
    // Serializer state machine (240MHz domain)
    always @(posedge clk_240m_tx or negedge rst_n_240m_tx) begin
        if (!rst_n_240m_tx) begin
            serif_state <= SERIF_STATE_DISABLED;
            serializer_enable_reg <= 1'b0;
            serializer_reset_n_reg <= 1'b1;  // No reset initially
            serializer_active_reg <= 1'b0;
            serializer_status_reg <= 1'b0;
            if_error_reg <= 1'b0;
            error_count <= 3'd0;
            clock_divider <= 2'b00;
            clock_enable <= 1'b0;
        end else begin
            case (serif_state)
                SERIF_STATE_DISABLED: begin
                    serializer_enable_reg <= 1'b0;
                    serializer_reset_n_reg <= 1'b0;  // Assert reset
                    serializer_active_reg <= 1'b0;
                    if (tx_en && !serializer_bypass) begin
                        serif_state <= SERIF_STATE_RESET;
                    end
                end
                
                SERIF_STATE_RESET: begin
                    // Hold reset for a few cycles
                    if (clock_divider < 2'b11) begin
                        clock_divider <= clock_divider + 1;
                    end else begin
                        serializer_reset_n_reg <= 1'b1;  // Release reset
                        serif_state <= SERIF_STATE_CONFIG;
                        clock_divider <= 2'b00;
                    end
                end
                
                SERIF_STATE_CONFIG: begin
                    serializer_enable_reg <= 1'b1;
                    if (serializer_ready) begin
                        serif_state <= SERIF_STATE_STARTING;
                        clock_enable <= 1'b1;
                    end
                end
                
                SERIF_STATE_STARTING: begin
                    serializer_active_reg <= 1'b1;
                    if (tx_serial_valid_240m || tx_idle_pattern_240m) begin
                        serif_state <= SERIF_STATE_ACTIVE;
                    end
                end
                
                SERIF_STATE_ACTIVE: begin
                    if (!tx_en) begin
                        serif_state <= SERIF_STATE_STOPPING;
                    end else if (serializer_error || !serializer_ready) begin
                        if (error_count < 3'd7) begin
                            error_count <= error_count + 1;
                        end else begin
                            serif_state <= SERIF_STATE_ERROR;
                            if_error_reg <= 1'b1;
                        end
                    end
                end
                
                SERIF_STATE_STOPPING: begin
                    if (clock_divider < 2'b11) begin
                        clock_divider <= clock_divider + 1;
                    end else begin
                        serializer_enable_reg <= 1'b0;
                        serializer_active_reg <= 1'b0;
                        clock_enable <= 1'b0;
                        serif_state <= SERIF_STATE_DISABLED;
                        clock_divider <= 2'b00;
                    end
                end
                
                SERIF_STATE_ERROR: begin
                    serializer_active_reg <= 1'b0;
                    serializer_enable_reg <= 1'b0;
                    if (!tx_en) begin
                        serif_state <= SERIF_STATE_DISABLED;
                        if_error_reg <= 1'b0;
                        error_count <= 3'd0;
                    end
                end
                
                default: begin
                    serif_state <= SERIF_STATE_ERROR;
                    if_error_reg <= 1'b1;
                end
            endcase
        end
    end
    
    // Data path control
    always @(posedge clk_240m_tx or negedge rst_n_240m_tx) begin
        if (!rst_n_240m_tx) begin
            serializer_data_reg <= 1'b0;
        end else if (serializer_bypass) begin
            // Bypass mode: pass data directly
            serializer_data_reg <= tx_serial_data_240m;
        end else if (tx_idle_pattern_240m) begin
            // Idle pattern: drive low
            serializer_data_reg <= 1'b0;
        end else if (tx_serial_valid_240m) begin
            // Normal operation
            serializer_data_reg <= tx_serial_data_240m;
        end else begin
            // No valid data: drive low
            serializer_data_reg <= 1'b0;
        end
    end
    
    // Serializer clock generation
    always @(posedge clk_240m_tx or negedge rst_n_240m_tx) begin
        if (!rst_n_240m_tx) begin
            serializer_clock_reg <= 1'b0;
        end else if (clock_enable) begin
            serializer_clock_reg <= !serializer_clock_reg;  // Divide by 2
        end else begin
            serializer_clock_reg <= 1'b0;
        end
    end
    
    // Status monitoring (24MHz domain)
    always @(posedge clk_24m or negedge rst_n_24m) begin
        if (!rst_n_24m) begin
            serializer_status_reg <= 1'b0;
        end else begin
            serializer_status_reg <= serializer_ready && !serializer_error;
        end
    end
    
    // Output assignments
    assign serializer_data = serializer_data_reg;
    assign serializer_enable = serializer_enable_reg;
    assign serializer_clock = serializer_clock_reg;
    assign serializer_reset_n = serializer_reset_n_reg;
    assign serializer_active = serializer_active_reg;
    assign serializer_status = serializer_status_reg;
    assign if_error = if_error_reg;

endmodule