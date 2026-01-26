/*
 * SerDes PHY Transmit Top Module
 * Transmit controller FSM integrating complete TX datapath
 * Orchestrates word_assembler → tx_fifo → tx_data_mux → manchester_encoder pipeline
 * Handles flow control, clock domain crossing, and status monitoring
 */

`default_nettype none

module serdesphy_tx_top (
    // Clock and reset
    input  wire       clk_24m,          // 24 MHz system clock
    input  wire       clk_240m_tx,      // 240 MHz TX clock (from PLL)
    input  wire       rst_n_24m,         // 24MHz domain reset
    input  wire       rst_n_240m_tx,     // 240MHz TX domain reset
    
    // Control inputs from CSR
    input  wire       tx_en,            // Transmit enable
    input  wire       tx_fifo_en,       // TX FIFO enable
    input  wire       tx_prbs_en,       // TX PRBS enable
    input  wire       tx_idle,          // Force idle pattern
    input  wire       tx_data_sel,      // TX data source select (0=FIFO, 1=PRBS)
    
    // External TX data interface
    input  wire [3:0] tx_data,          // 4-bit transmit data
    input  wire       tx_valid,         // TX data valid strobe
    
    // Serial output interface to analog serializer
    output wire       tx_serial_data,   // Serial data to serializer
    output wire       tx_serial_valid,  // Serial data valid
    output wire       tx_idle_pattern,  // Idle pattern indicator
    
    // Status outputs to CSR
    output wire       tx_fifo_full,     // TX FIFO full flag
    output wire       tx_fifo_empty,    // TX FIFO empty flag
    output wire       tx_overflow,      // TX FIFO overflow (sticky)
    output wire       tx_underflow,     // TX FIFO underflow (sticky)
    output wire       tx_active,        // TX data path active
    output wire       tx_error,         // TX error flag
    
    // Clock domain status
    input  wire       clk_240m_tx_en    // 240MHz TX clock enable
);

    // TX Controller State Machine
    localparam [2:0]
        TX_STATE_DISABLED  = 3'b000,  // TX disabled
        TX_STATE_IDLE      = 3'b001,  // TX enabled, idle
        TX_STATE_STARTING  = 3'b010,  // Starting TX pipeline
        TX_STATE_ACTIVE    = 3'b011,  // TX actively transmitting
        TX_STATE_STOPPING  = 3'b100,  // Stopping TX pipeline
        TX_STATE_ERROR     = 3'b101;  // Error state
    
    // Internal signals
    reg [2:0]   tx_state;
    reg [7:0]   word_assembled;
    reg         word_assembled_valid;
    reg [7:0]   fifo_data_out;
    reg         fifo_data_valid;
    reg         fifo_read_en;
    reg [7:0]   mux_data_out;
    reg         mux_data_valid;
    reg [15:0]  manchester_data_out;
    reg         manchester_data_valid;
    reg [3:0]   serial_shift_reg;
    reg [3:0]   serial_bit_count;
    reg         tx_serial_data_reg;
    reg         tx_serial_valid_reg;
    reg         tx_idle_pattern_reg;
    reg         tx_active_reg;
    reg         tx_error_reg;
    reg [2:0]   error_count;
    
    // Word assembler interface
    wire [7:0]  word_assembler_out;
    wire        word_assembler_valid;
    
    // TX FIFO interface
    wire [7:0]  tx_fifo_data_out;
    wire        tx_fifo_empty_wire;
    wire        tx_fifo_full_wire;
    wire        tx_fifo_overflow_wire;
    wire        tx_fifo_underflow_wire;
    
    // PRBS generator interface
    wire [7:0]  prbs_data_out;
    wire        prbs_data_valid;
    
    // Data multiplexer interface
    wire [7:0]  tx_mux_data_out;
    wire        tx_mux_data_valid;
    
    // Manchester encoder interface
    wire [15:0] manchester_encoder_out;
    wire        manchester_encoder_valid;
    wire        manchester_encoder_error;
    
    // Sticky error registers
    reg         overflow_sticky;
    reg         underflow_sticky;
    reg         manchester_error_sticky;
    
    // Additional interface wires
    wire        word_assembler_ready;
    wire        fifo_read_valid;
    wire        mux_fifo_ready;
    wire        mux_prbs_ready;
    wire        mux_output_ready;

    // Instantiate word assembler
    serdesphy_word_assembler u_word_assembler (
        .clk            (clk_24m),
        .rst_n          (rst_n_24m),
        .tx_data_nibble (tx_data),
        .tx_valid       (tx_valid && tx_en && tx_fifo_en),
        .tx_data_word   (word_assembler_out),
        .tx_word_valid  (word_assembler_valid),
        .tx_word_ready  (word_assembler_ready)
    );

    // Instantiate TX FIFO
    serdesphy_tx_fifo u_tx_fifo (
        .clk          (clk_24m),
        .rst_n        (rst_n_24m),
        .enable       (tx_en && tx_fifo_en),
        .write_enable (1'b1),
        .read_enable  (mux_fifo_ready),
        .data_in      (word_assembler_out),
        .write_valid  (word_assembler_valid),
        .data_out     (tx_fifo_data_out),
        .read_valid   (fifo_read_valid),
        .full         (tx_fifo_full_wire),
        .empty        (tx_fifo_empty_wire),
        .overflow     (tx_fifo_overflow_wire),
        .underflow    (tx_fifo_underflow_wire)
    );

    // Instantiate PRBS generator
    serdesphy_prbs_generator u_prbs_generator (
        .clk           (clk_24m),
        .rst_n         (rst_n_24m),
        .enable        (tx_en && tx_prbs_en),
        .reset_pattern (1'b0),
        .prbs_data     (prbs_data_out),
        .prbs_valid    (prbs_data_valid),
        .prbs_ready    (mux_prbs_ready)
    );

    // Instantiate TX data multiplexer
    serdesphy_tx_data_mux u_tx_data_mux (
        .clk          (clk_24m),
        .rst_n        (rst_n_24m),
        .enable       (tx_en),
        .tx_idle      (tx_idle),
        .tx_data_sel  (tx_data_sel),
        .fifo_data    (tx_fifo_data_out),
        .fifo_valid   (fifo_read_valid),
        .fifo_ready   (mux_fifo_ready),
        .prbs_data    (prbs_data_out),
        .prbs_valid   (prbs_data_valid),
        .prbs_ready   (mux_prbs_ready),
        .output_data  (tx_mux_data_out),
        .output_valid (tx_mux_data_valid),
        .output_ready (mux_output_ready)
    );

    // Instantiate Manchester encoder
    serdesphy_manchester_encoder u_manchester_encoder (
        .clk             (clk_24m),
        .rst_n           (rst_n_24m),
        .data_in         (tx_mux_data_out),
        .data_valid      (tx_mux_data_valid),
        .manchester_data (manchester_encoder_out),
        .manchester_valid(manchester_encoder_valid),
        .serializer_ready(mux_output_ready)
    );

    // Manchester encoder doesn't have error output - derive from valid
    assign manchester_encoder_error = 1'b0;
    
    // TX Controller State Machine
    always @(posedge clk_24m or negedge rst_n_24m) begin
        if (!rst_n_24m) begin
            tx_state <= TX_STATE_DISABLED;
            tx_active_reg <= 1'b0;
            tx_error_reg <= 1'b0;
            error_count <= 3'd0;
            overflow_sticky <= 1'b0;
            underflow_sticky <= 1'b0;
            manchester_error_sticky <= 1'b0;
        end else begin
            case (tx_state)
                TX_STATE_DISABLED: begin
                    tx_active_reg <= 1'b0;
                    if (tx_en && clk_240m_tx_en) begin
                        tx_state <= TX_STATE_IDLE;
                    end
                end
                
                TX_STATE_IDLE: begin
                    if (!tx_en || !clk_240m_tx_en) begin
                        tx_state <= TX_STATE_DISABLED;
                    end else if (tx_idle) begin
                        tx_active_reg <= 1'b0;
                        tx_idle_pattern_reg <= 1'b1;
                    end else if ((tx_fifo_en && word_assembler_valid) || 
                               (tx_prbs_en && prbs_data_valid)) begin
                        tx_state <= TX_STATE_STARTING;
                    end
                end
                
                TX_STATE_STARTING: begin
                    tx_active_reg <= 1'b1;
                    tx_idle_pattern_reg <= 1'b0;
                    if (manchester_encoder_valid) begin
                        tx_state <= TX_STATE_ACTIVE;
                    end
                end
                
                TX_STATE_ACTIVE: begin
                    if (!tx_en || !clk_240m_tx_en) begin
                        tx_state <= TX_STATE_STOPPING;
                    end else if (tx_idle) begin
                        tx_state <= TX_STATE_IDLE;
                    end else if (manchester_encoder_error || tx_fifo_underflow_wire) begin
                        if (error_count < 3'd7) begin
                            error_count <= error_count + 1;
                        end else begin
                            tx_state <= TX_STATE_ERROR;
                            tx_error_reg <= 1'b1;
                        end
                    end
                end
                
                TX_STATE_STOPPING: begin
                    if (!manchester_encoder_valid) begin
                        tx_active_reg <= 1'b0;
                        tx_state <= TX_STATE_DISABLED;
                    end
                end
                
                TX_STATE_ERROR: begin
                    tx_active_reg <= 1'b0;
                    if (!tx_en) begin
                        tx_state <= TX_STATE_DISABLED;
                        tx_error_reg <= 1'b0;
                        error_count <= 3'd0;
                    end
                end
                
                default: begin
                    tx_state <= TX_STATE_ERROR;
                    tx_error_reg <= 1'b1;
                end
            endcase
        end
    end
    
    // FIFO read enable logic
    always @(posedge clk_24m or negedge rst_n_24m) begin
        if (!rst_n_24m) begin
            fifo_read_en <= 1'b0;
        end else begin
            // Read from FIFO when enabled and data available
            fifo_read_en <= tx_en && tx_fifo_en && !tx_fifo_empty_wire && 
                           !tx_idle && (tx_data_sel == 1'b0);
        end
    end
    
    // Sticky error handling
    always @(posedge clk_24m or negedge rst_n_24m) begin
        if (!rst_n_24m) begin
            overflow_sticky <= 1'b0;
            underflow_sticky <= 1'b0;
            manchester_error_sticky <= 1'b0;
        end else begin
            if (tx_fifo_overflow_wire) overflow_sticky <= 1'b1;
            if (tx_fifo_underflow_wire) underflow_sticky <= 1'b1;
            if (manchester_encoder_error) manchester_error_sticky <= 1'b0;
        end
    end
    
    // Serial output generation (240MHz domain)
    always @(posedge clk_240m_tx or negedge rst_n_240m_tx) begin
        if (!rst_n_240m_tx) begin
            serial_shift_reg <= 4'b0000;
            serial_bit_count <= 4'd0;
            tx_serial_data_reg <= 1'b0;
            tx_serial_valid_reg <= 1'b0;
            tx_idle_pattern_reg <= 1'b1;
        end else if (clk_240m_tx_en) begin
            if (tx_idle) begin
                tx_serial_data_reg <= 1'b0;
                tx_serial_valid_reg <= 1'b0;
                tx_idle_pattern_reg <= 1'b1;
            end else if (manchester_encoder_valid && serial_bit_count == 4'd0) begin
                // Load new 16-bit Manchester data
                serial_shift_reg <= manchester_encoder_out[15:12];
                serial_bit_count <= 4'd12;
                tx_serial_data_reg <= manchester_encoder_out[15];
                tx_serial_valid_reg <= 1'b1;
            end else if (serial_bit_count > 0) begin
                // Shift out remaining bits
                serial_shift_reg <= {serial_shift_reg[2:0], 1'b0};
                serial_bit_count <= serial_bit_count - 1;
                tx_serial_data_reg <= serial_shift_reg[3];
                tx_serial_valid_reg <= 1'b1;
            end else begin
                tx_serial_data_reg <= 1'b0;
                tx_serial_valid_reg <= 1'b0;
            end
        end else begin
            tx_serial_data_reg <= 1'b0;
            tx_serial_valid_reg <= 1'b0;
        end
    end
    
    // Output assignments
    assign tx_serial_data = tx_serial_data_reg;
    assign tx_serial_valid = tx_serial_valid_reg;
    assign tx_idle_pattern = tx_idle_pattern_reg;
    
    // Status outputs
    assign tx_fifo_full = tx_fifo_full_wire;
    assign tx_fifo_empty = tx_fifo_empty_wire;
    assign tx_overflow = overflow_sticky;
    assign tx_underflow = underflow_sticky;
    assign tx_active = tx_active_reg;
    assign tx_error = tx_error_reg || manchester_error_sticky;

endmodule