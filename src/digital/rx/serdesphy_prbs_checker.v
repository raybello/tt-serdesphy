/*
 * SerDes PHY PRBS Checker
 * PRBS-7 sequence checker with error detection
 * Compares decoded data against expected PRBS-7 sequence
 * Single-bit error detection per 8-bit word
 * Error counter saturates at 255
 */

`default_nettype none

module serdesphy_prbs_checker (
    // Clock and reset
    input  wire        clk,            // 24 MHz clock
    input  wire        rst_n,          // Active-low reset
    
    // Control signals
    input  wire        enable,         // Enable PRBS checker
    input  wire        reset_counter,   // Reset error counter
    input  wire        reset_alignment, // Reset alignment FSM
    
    // Input interface
    input  wire [7:0]  received_data, // 8-bit received data
    input  wire        data_valid,    // Received data valid
    
    // Output interface
    output wire        prbs_error,    // PRBS error detected (sticky)
    output wire [7:0] error_count,   // Error counter
    output wire        checker_busy   // Checker busy flag
);

    // Internal registers
    reg [6:0] prbs_shift_reg;    // Expected PRBS LFSR
    reg [7:0] expected_data_reg;
    reg [7:0] error_counter_reg;
    reg        error_detected_reg;
    reg        sticky_error_reg;
    reg [1:0] checker_state;
    reg        busy_flag;
    
    // State encoding
    localparam STATE_IDLE        = 2'b00;
    localparam STATE_CHECKING    = 2'b01;
    localparam STATE_ERROR       = 2'b10;
    localparam STATE_READY       = 2'b11;
    
    // Unrolled PRBS-7 computation from current prbs_shift_reg.
    // Matches generate_expected_prbs(): each output bit is the MSB of the
    // LFSR after i steps; the new LFSR state is the lower 7 bits (bits [6:0]).
    wire [7:0] prbs_next_byte = {prbs_shift_reg[6] ^ prbs_shift_reg[5],
                                  prbs_shift_reg[0], prbs_shift_reg[1],
                                  prbs_shift_reg[2], prbs_shift_reg[3],
                                  prbs_shift_reg[4], prbs_shift_reg[5],
                                  prbs_shift_reg[6]};
    wire [6:0] prbs_next_state = {prbs_shift_reg[0], prbs_shift_reg[1],
                                   prbs_shift_reg[2], prbs_shift_reg[3],
                                   prbs_shift_reg[4], prbs_shift_reg[5],
                                   prbs_shift_reg[6]};

    // PRBS checker state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            checker_state <= STATE_IDLE;
            prbs_shift_reg <= 7'h7F;  // Non-zero initial state
            expected_data_reg <= 8'h00;
            error_counter_reg <= 8'h00;
            error_detected_reg <= 0;
            sticky_error_reg <= 0;
            busy_flag <= 1'b0;
        end else if (reset_alignment) begin
            checker_state <= STATE_IDLE;
            prbs_shift_reg <= 7'h7F;  // Reset alignment
            expected_data_reg <= 8'h00;
            error_detected_reg <= 0;
            busy_flag <= 1'b0;
        end else if (reset_counter) begin
            error_counter_reg <= 8'h00;
            sticky_error_reg <= 0;
        end else if (!enable) begin
            checker_state <= STATE_IDLE;
            busy_flag <= 1'b0;
        end else begin
            case (checker_state)
                STATE_IDLE: begin
                    error_detected_reg <= 0;
                    busy_flag <= 1'b0;
                    if (data_valid) begin
                        expected_data_reg <= prbs_next_byte;
                        prbs_shift_reg    <= prbs_next_state;
                        checker_state     <= STATE_CHECKING;
                    end
                end
                
                STATE_CHECKING: begin
                    busy_flag <= 1'b1;
                    // Check for errors
                    if (received_data != expected_data_reg) begin
                        error_detected_reg <= 1;
                        sticky_error_reg <= 1;
                        // Increment error counter (saturate at 255)
                        if (error_counter_reg < 8'hFF) begin
                            error_counter_reg <= error_counter_reg + 1;
                        end
                        checker_state <= STATE_ERROR;
                    end else begin
                        error_detected_reg <= 0;
                        checker_state <= STATE_READY;
                    end
                end
                
                STATE_ERROR: begin
                    error_detected_reg <= 1;
                    checker_state <= STATE_READY;
                end
                
                STATE_READY: begin
                    error_detected_reg <= 0;
                    busy_flag <= 1'b0;
                    checker_state <= STATE_IDLE;
                end
                
                default: begin
                    checker_state <= STATE_IDLE;
                end
            endcase
        end
    end
    
    // Output assignments
    assign prbs_error = sticky_error_reg;
    assign error_count = error_counter_reg;
    assign checker_busy = busy_flag;

endmodule