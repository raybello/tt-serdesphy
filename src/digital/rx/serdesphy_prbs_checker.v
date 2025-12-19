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
    
    // PRBS-7 LFSR polynomial: x^7 + x^6 + 1
    function [6:0] lfsr_next;
        input [6:0] current_state;
        begin
            lfsr_next = {current_state[5:0], 
                        current_state[6] ^ current_state[5]};
        end
    endfunction
    
    // Generate expected 8-bit PRBS sequence
    function [7:0] generate_expected_prbs;
        input [6:0] initial_state;
        reg [6:0] temp_state;
        integer i;
        begin
            temp_state = initial_state;
            generate_expected_prbs = 8'b0;
            
            for (i = 0; i < 8; i = i + 1) begin
                generate_expected_prbs[i] = temp_state[6];  // Output MSB
                temp_state = lfsr_next(temp_state);
            end
        end
    endfunction
    
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
                        // Generate expected PRBS
                        expected_data_reg <= generate_expected_prbs(prbs_shift_reg);
                        // Update LFSR for next cycle
                        prbs_shift_reg <= generate_expected_prbs(prbs_shift_reg);
                        checker_state <= STATE_CHECKING;
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