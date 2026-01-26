/*
 * SerDes PHY Receive Top Module
 * Receive controller FSM with alignment and synchronization
 * Orchestrates manchester_decoder → rx_fifo → word_disassembler pipeline
 * Handles clock domain crossing, alignment, and error detection
 */

`default_nettype none

module serdesphy_rx_top (
    // Clock and reset
    input  wire       clk_24m,          // 24 MHz system clock
    input  wire       clk_240m_rx,      // 240 MHz RX clock (from CDR)
    input  wire       rst_n_24m,         // 24MHz domain reset
    input  wire       rst_n_240m_rx,     // 240MHz RX domain reset
    
    // Control inputs from CSR
    input  wire       rx_en,            // Receive enable
    input  wire       rx_fifo_en,       // RX FIFO enable
    input  wire       rx_prbs_chk_en,   // RX PRBS check enable
    input  wire       rx_align_rst,     // Reset alignment FSM
    input  wire       rx_data_sel,      // RX output select (0=FIFO, 1=PRBS status)
    
    // Serial input interface from analog deserializer
    input  wire       rx_serial_data,   // Serial data from deserializer
    input  wire       rx_serial_valid,  // Serial data valid
    input  wire       rx_serial_error,  // Serial data error
    
    // External RX data interface
    output wire [3:0] rx_data,          // 4-bit receive data
    output wire       rx_valid,         // RX data valid strobe
    
    // Status outputs to CSR
    output wire       rx_fifo_full,     // RX FIFO full flag
    output wire       rx_fifo_empty,    // RX FIFO empty flag
    output wire       rx_overflow,      // RX FIFO overflow (sticky)
    output wire       rx_underflow,     // RX FIFO underflow (sticky)
    output wire       rx_active,        // RX data path active
    output wire       rx_error,         // RX error flag
    output wire       rx_aligned,       // RX alignment achieved
    output wire       prbs_err,         // PRBS error indication

    // Clock domain status
    input  wire       clk_240m_rx_en    // 240MHz RX clock enable
);

    // RX Controller State Machine
    localparam [2:0]
        RX_STATE_DISABLED  = 3'b000,  // RX disabled
        RX_STATE_ALIGNING  = 3'b001,  // Aligning to Manchester pattern
        RX_STATE_ACQUIRING = 3'b010,  // Acquiring bit/word synchronization
        RX_STATE_ACTIVE    = 3'b011,  // RX actively receiving
        RX_STATE_ERROR     = 3'b100;  // Error state
    
    // Alignment FSM states
    localparam [1:0]
        ALIGN_STATE_SEARCH   = 2'b00,  // Search for Manchester pattern
        ALIGN_STATE_VERIFY   = 2'b01,  // Verify pattern stability
        ALIGN_STATE_LOCKED   = 2'b10;  // Pattern locked
    
    // Internal signals
    reg [2:0]   rx_state;
    reg [1:0]   align_state;
    reg [15:0]  serial_shift_reg;
    reg [3:0]   serial_bit_count;
    reg [15:0]  manchester_word_reg;
    reg         manchester_word_valid;
    reg         rx_active_reg;
    reg         rx_error_reg;
    reg         rx_aligned_reg;
    reg [7:0]   manchester_data_out;
    reg         manchester_data_valid;
    reg         fifo_write_enable;
    reg         fifo_read_enable;
    reg [2:0]   error_count;
    reg [7:0]   align_count;
    reg [7:0]   verify_count;
    
    // Manchester decoder interface
    wire [7:0]  manchester_decoder_out;
    wire        manchester_decoder_valid;
    wire        manchester_decoder_error;
    
    // RX FIFO interface
    wire [7:0]  rx_fifo_data_out;
    wire        rx_fifo_empty_wire;
    wire        rx_fifo_full_wire;
    wire        rx_fifo_overflow_wire;
    wire        rx_fifo_underflow_wire;
    wire        rx_fifo_rd_valid;
    
    // Word disassembler interface
    wire [3:0]  word_disassembler_out;
    wire        word_disassembler_valid;
    
    // PRBS checker interface
    wire        prbs_error_wire;
    wire [7:0]  prbs_error_count;
    
    // Sticky error registers
    reg         overflow_sticky;
    reg         underflow_sticky;
    reg         manchester_error_sticky;
    reg         serial_error_sticky;
    
    // Manchester pattern detection
    reg [1:0]   transition_pattern;
    reg         pattern_detected;
    
    // Additional interface wires
    wire        word_disassembler_ready;
    wire        prbs_checker_busy;

    // Instantiate Manchester decoder
    serdesphy_manchester_decoder u_manchester_decoder (
        .clk             (clk_24m),
        .rst_n           (rst_n_24m),
        .manchester_data (manchester_word_reg),
        .data_valid      (manchester_word_valid && rx_en && rx_aligned_reg),
        .decoded_data    (manchester_decoder_out),
        .decode_valid    (manchester_decoder_valid),
        .decode_error    (manchester_decoder_error)
    );

    // Instantiate RX FIFO
    serdesphy_rx_fifo u_rx_fifo (
        // Write clock domain (24MHz recovered)
        .wr_clk          (clk_24m),
        .wr_rst_n        (rst_n_24m),
        .wr_enable       (rx_en && rx_fifo_en),
        .wr_data         (manchester_decoder_out),
        .wr_valid        (manchester_decoder_valid),

        // Read clock domain (24MHz system)
        .rd_clk          (clk_24m),
        .rd_rst_n        (rst_n_24m),
        .rd_enable       (rx_en && rx_fifo_en),
        .rd_data         (rx_fifo_data_out),
        .rd_valid        (rx_fifo_rd_valid),
        .rd_read_enable  (word_disassembler_ready),

        // Status flags
        .full            (rx_fifo_full_wire),
        .empty           (rx_fifo_empty_wire),
        .overflow        (rx_fifo_overflow_wire),
        .underflow       (rx_fifo_underflow_wire)
    );

    // Instantiate word disassembler
    serdesphy_word_disassembler u_word_disassembler (
        .clk            (clk_24m),
        .rst_n          (rst_n_24m),
        .rx_data_word   (rx_fifo_data_out),
        .rx_word_valid  (rx_fifo_rd_valid && rx_en && rx_fifo_en),
        .rx_data_nibble (word_disassembler_out),
        .rx_valid       (word_disassembler_valid),
        .rx_word_ready  (word_disassembler_ready)
    );

    // Instantiate PRBS checker
    serdesphy_prbs_checker u_prbs_checker (
        .clk             (clk_24m),
        .rst_n           (rst_n_24m),
        .enable          (rx_en && rx_prbs_chk_en),
        .reset_counter   (rx_align_rst),
        .reset_alignment (rx_align_rst),
        .received_data   (manchester_decoder_out),
        .data_valid      (manchester_decoder_valid),
        .prbs_error      (prbs_error_wire),
        .error_count     (prbs_error_count),
        .checker_busy    (prbs_checker_busy)
    );
    
    // Serial input accumulation (240MHz domain)
    always @(posedge clk_240m_rx or negedge rst_n_240m_rx) begin
        if (!rst_n_240m_rx) begin
            serial_shift_reg <= 16'h0000;
            serial_bit_count <= 4'd0;
            manchester_word_reg <= 16'h0000;
            manchester_word_valid <= 1'b0;
        end else if (clk_240m_rx_en && rx_en) begin
            if (rx_serial_valid && !rx_serial_error) begin
                if (serial_bit_count == 4'd0) begin
                    // Start new 16-bit word
                    serial_shift_reg <= {15'h0000, rx_serial_data};
                    serial_bit_count <= 4'd1;
                end else if (serial_bit_count < 4'd15) begin
                    // Continue accumulation
                    serial_shift_reg <= {serial_shift_reg[14:0], rx_serial_data};
                    serial_bit_count <= serial_bit_count + 1;
                end else begin
                    // Word complete
                    manchester_word_reg <= {serial_shift_reg[14:0], rx_serial_data};
                    manchester_word_valid <= 1'b1;
                    serial_bit_count <= 4'd0;
                end
            end else begin
                manchester_word_valid <= 1'b0;
            end
        end else begin
            manchester_word_valid <= 1'b0;
        end
    end
    
    // RX Controller State Machine
    always @(posedge clk_24m or negedge rst_n_24m) begin
        if (!rst_n_24m) begin
            rx_state <= RX_STATE_DISABLED;
            rx_active_reg <= 1'b0;
            rx_error_reg <= 1'b0;
            rx_aligned_reg <= 1'b0;
            error_count <= 3'd0;
            overflow_sticky <= 1'b0;
            underflow_sticky <= 1'b0;
            manchester_error_sticky <= 1'b0;
            serial_error_sticky <= 1'b0;
        end else begin
            case (rx_state)
                RX_STATE_DISABLED: begin
                    rx_active_reg <= 1'b0;
                    rx_aligned_reg <= 1'b0;
                    if (rx_en && clk_240m_rx_en) begin
                        rx_state <= RX_STATE_ALIGNING;
                    end
                end
                
                RX_STATE_ALIGNING: begin
                    if (!rx_en || !clk_240m_rx_en) begin
                        rx_state <= RX_STATE_DISABLED;
                    end else if (rx_align_rst) begin
                        align_state <= ALIGN_STATE_SEARCH;
                        align_count <= 8'd0;
                        verify_count <= 8'd0;
                    end else if (rx_aligned_reg) begin
                        rx_state <= RX_STATE_ACQUIRING;
                    end else begin
                        // Alignment logic in separate always block
                    end
                end
                
                RX_STATE_ACQUIRING: begin
                    if (!rx_en || !clk_240m_rx_en) begin
                        rx_state <= RX_STATE_DISABLED;
                        rx_aligned_reg <= 1'b0;
                    end else if (manchester_data_valid) begin
                        rx_active_reg <= 1'b1;
                        rx_state <= RX_STATE_ACTIVE;
                    end
                end
                
                RX_STATE_ACTIVE: begin
                    if (!rx_en || !clk_240m_rx_en) begin
                        rx_state <= RX_STATE_DISABLED;
                        rx_active_reg <= 1'b0;
                    end else if (!rx_aligned_reg) begin
                        rx_state <= RX_STATE_ALIGNING;
                    end else if (manchester_decoder_error || rx_fifo_overflow_wire || 
                               rx_serial_error || prbs_error_wire) begin
                        if (error_count < 3'd7) begin
                            error_count <= error_count + 1;
                        end else begin
                            rx_state <= RX_STATE_ERROR;
                            rx_error_reg <= 1'b1;
                        end
                    end
                end
                
                RX_STATE_ERROR: begin
                    rx_active_reg <= 1'b0;
                    if (!rx_en) begin
                        rx_state <= RX_STATE_DISABLED;
                        rx_error_reg <= 1'b0;
                        error_count <= 3'd0;
                    end
                end
                
                default: begin
                    rx_state <= RX_STATE_ERROR;
                    rx_error_reg <= 1'b1;
                end
            endcase
        end
    end
    
    // Alignment state machine
    always @(posedge clk_24m or negedge rst_n_24m) begin
        if (!rst_n_24m || rx_align_rst) begin
            align_state <= ALIGN_STATE_SEARCH;
            align_count <= 8'd0;
            verify_count <= 8'd0;
            rx_aligned_reg <= 1'b0;
        end else if (rx_state == RX_STATE_ALIGNING) begin
            case (align_state)
                ALIGN_STATE_SEARCH: begin
                    // Look for Manchester transition pattern in serial stream
                    if (manchester_word_valid) begin
                        // Simple pattern detection: look for alternating bits
                        if (pattern_detected) begin
                            align_count <= align_count + 1;
                            if (align_count >= 8'd10) begin  // Found 10 valid patterns
                                align_state <= ALIGN_STATE_VERIFY;
                                verify_count <= 8'd0;
                            end
                        end else begin
                            align_count <= 8'd0;
                        end
                    end
                end
                
                ALIGN_STATE_VERIFY: begin
                    if (manchester_word_valid) begin
                        if (pattern_detected) begin
                            verify_count <= verify_count + 1;
                            if (verify_count >= 8'd20) begin  // Verified 20 more patterns
                                align_state <= ALIGN_STATE_LOCKED;
                                rx_aligned_reg <= 1'b1;
                            end
                        end else begin
                            align_state <= ALIGN_STATE_SEARCH;
                            align_count <= 8'd0;
                        end
                    end
                end
                
                ALIGN_STATE_LOCKED: begin
                    // Check for loss of alignment
                    if (manchester_word_valid && !pattern_detected) begin
                        align_state <= ALIGN_STATE_SEARCH;
                        align_count <= 8'd0;
                        rx_aligned_reg <= 1'b0;
                    end
                end
                
                default: begin
                    align_state <= ALIGN_STATE_SEARCH;
                end
            endcase
        end
    end
    
    // Pattern detection logic
    always @(posedge clk_24m or negedge rst_n_24m) begin
        if (!rst_n_24m) begin
            transition_pattern <= 2'b00;
            pattern_detected <= 1'b0;
        end else if (manchester_word_valid) begin
            // Simple Manchester pattern detection: look for alternating transitions
            // This is a simplified approach - real implementation would be more sophisticated
            transition_pattern <= {transition_pattern[0], manchester_word_reg[0]};
            pattern_detected <= (transition_pattern == 2'b01) || (transition_pattern == 2'b10);
        end
    end
    
    // Data flow control
    always @(posedge clk_24m or negedge rst_n_24m) begin
        if (!rst_n_24m) begin
            manchester_data_valid <= 1'b0;
            fifo_write_enable <= 1'b0;
            fifo_read_enable <= 1'b0;
        end else begin
            // Feed Manchester decoder output to FIFO
            manchester_data_out <= manchester_decoder_out;
            manchester_data_valid <= manchester_decoder_valid && !rx_fifo_full_wire;
            
            // Read from FIFO when data available
            fifo_read_enable <= rx_en && rx_fifo_en && !rx_fifo_empty_wire;
        end
    end
    
    // Sticky error handling
    always @(posedge clk_24m or negedge rst_n_24m) begin
        if (!rst_n_24m) begin
            overflow_sticky <= 1'b0;
            underflow_sticky <= 1'b0;
            manchester_error_sticky <= 1'b0;
            serial_error_sticky <= 1'b0;
        end else begin
            if (rx_fifo_overflow_wire) overflow_sticky <= 1'b1;
            if (rx_fifo_underflow_wire) underflow_sticky <= 1'b1;
            if (manchester_decoder_error) manchester_error_sticky <= 1'b1;
            if (rx_serial_error) serial_error_sticky <= 1'b1;
        end
    end
    
    // Output multiplexing based on rx_data_sel
    assign rx_data = rx_data_sel ? prbs_error_count[3:0] : word_disassembler_out;
    assign rx_valid = rx_data_sel ? 1'b1 : word_disassembler_valid;
    
    // Status outputs
    assign rx_fifo_full = rx_fifo_full_wire;
    assign rx_fifo_empty = rx_fifo_empty_wire;
    assign rx_overflow = overflow_sticky;
    assign rx_underflow = underflow_sticky;
    assign rx_active = rx_active_reg;
    assign rx_error = rx_error_reg || manchester_error_sticky || serial_error_sticky;
    assign rx_aligned = rx_aligned_reg;
    assign prbs_err = prbs_error_wire;

endmodule