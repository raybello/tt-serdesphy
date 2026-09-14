/*
 * SerDes PHY Transmit Data Multiplexer
 * Selects between FIFO output or PRBS generator
 * Controlled by TX_DATA_SEL register bit
 */

`default_nettype none

module serdesphy_tx_data_mux (
    // Clock and reset
    input  wire        clk,            // 24 MHz clock
    input  wire        rst_n,          // Active-low reset
    
    // Control signals
    input  wire        enable,         // Enable multiplexer
    input  wire        tx_idle,        // Force idle pattern (all zeros)
    input  wire        tx_data_sel,    // 0=PRBS, 1=FIFO - this module's own
                                        // STATE_SELECT branch below and
                                        // prbs_ready's derivation are the
                                        // actual, live definition of this
                                        // polarity; every OTHER "0=FIFO,
                                        // 1=PRBS" comment on tx_data_sel
                                        // elsewhere in the TX path (this
                                        // used to be one of them) was
                                        // backwards relative to this
    
    // FIFO data interface
    input  wire [7:0]  fifo_data,      // 8-bit FIFO data
    input  wire        fifo_valid,     // FIFO data valid
    output wire        fifo_ready,     // FIFO ready for new data
    
    // PRBS data interface
    input  wire [7:0]  prbs_data,      // 8-bit PRBS data
    input  wire        prbs_valid,     // PRBS data valid
    output wire        prbs_ready,     // PRBS ready for new data
    
    // Output interface (to Manchester encoder)
    output wire [7:0]  mux_data,       // 8-bit multiplexed data
    output wire        mux_valid,      // Multiplexed data valid
    input  wire        mux_ready       // Ready for multiplexed data
);

    // Internal signals
    reg [7:0]  output_data_reg;
    reg         output_valid_reg;
    reg         fifo_ready_reg;
    reg [1:0]  mux_state;
    
    // State encoding
    localparam STATE_IDLE     = 2'b00;
    localparam STATE_SELECT   = 2'b01;
    localparam STATE_OUTPUT   = 2'b10;
    localparam STATE_READY    = 2'b11;
    
    // Multiplexer state machine
    //
    // FIFO protocol:
    //   fifo_valid  = FIFO !empty (lookahead, independent of fifo_ready)
    //   fifo_ready  = pop-enable: assert for ONE cycle to advance FIFO read ptr
    //
    // Capture sequence (FIFO path):
    //   Cycle 1 (SELECT, !output_valid): see fifo_valid → latch data, set output_valid=1,
    //                                    assert fifo_ready=1 (pop fires on THIS posedge: rp++)
    //   Cycle 2 (SELECT,  output_valid): deassert fifo_ready=0, go to OUTPUT
    //
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mux_state <= STATE_IDLE;
            output_data_reg <= 8'h00;
            output_valid_reg <= 0;
            fifo_ready_reg <= 0;
        end else if (!enable) begin
            mux_state <= STATE_IDLE;
            output_data_reg <= 8'h00;
            output_valid_reg <= 0;
            fifo_ready_reg <= 0;
        end else begin
            case (mux_state)
                STATE_IDLE: begin
                    output_valid_reg <= 0;
                    fifo_ready_reg   <= 1'b0;  // No pop in IDLE
                    mux_state        <= STATE_SELECT;
                end

                STATE_SELECT: begin
                    if (!output_valid_reg) begin
                        // Waiting to capture data
                        if (tx_idle) begin
                            output_data_reg <= 8'h00;
                            output_valid_reg <= 1;
                        end else if (tx_data_sel == 1'b1) begin
                            // FIFO path: fifo_valid is high when FIFO !empty (lookahead)
                            if (fifo_valid) begin
                                output_data_reg  <= fifo_data;
                                output_valid_reg <= 1;
                                fifo_ready_reg   <= 1'b1;  // Pop: rp advances THIS posedge
                            end
                        end else begin
                            // PRBS path
                            if (prbs_valid) begin
                                output_data_reg  <= prbs_data;
                                output_valid_reg <= 1;
                                fifo_ready_reg   <= 1'b0;
                            end
                        end
                    end else begin
                        // Data captured; deassert pop and move to OUTPUT
                        fifo_ready_reg <= 1'b0;
                        mux_state      <= STATE_OUTPUT;
                    end
                end

                STATE_OUTPUT: begin
                    if (mux_ready) begin
                        output_valid_reg <= 0;
                        mux_state        <= STATE_READY;
                    end
                end

                STATE_READY: begin
                    fifo_ready_reg <= 1'b0;
                    mux_state      <= STATE_IDLE;
                end

                default: begin
                    mux_state <= STATE_IDLE;
                end
            endcase
        end
    end

    // Output assignments
    assign mux_data = output_data_reg;
    assign mux_valid = output_valid_reg;
    assign fifo_ready = fifo_ready_reg;

    // prbs_ready: unlike fifo_ready (an explicit single-cycle pop pulse,
    // asserted only exactly when a FIFO word is actually consumed),
    // prbs_ready was previously a REGISTER proactively set to 1 a state
    // (or two) ahead of actually being ready to capture - in STATE_IDLE,
    // a full cycle before this mux even reaches STATE_SELECT, and again
    // in STATE_READY, a cycle before returning to STATE_IDLE. Since
    // serdesphy_prbs_generator.v's STATE_IDLE and STATE_OUTPUT both
    // advance (generate a new byte) the moment they see prbs_ready high,
    // that early/premature assertion let the generator race ahead and
    // produce - and silently lose, since this mux only samples whatever
    // prbs_data happens to be present at the single cycle it actually
    // checks prbs_valid in STATE_SELECT - roughly every other byte before
    // this mux was ever in a state to capture it. Fixed by deriving
    // prbs_ready combinationally from this mux's own live state instead:
    // true only during the exact cycles this mux is actually waiting in
    // STATE_SELECT with nothing captured yet, mirroring fifo_ready's
    // already-correct "pulse only at the moment of real consumption"
    // shape.
    assign prbs_ready = (mux_state == STATE_SELECT) && !output_valid_reg &&
                         !tx_idle && (tx_data_sel == 1'b0);

endmodule