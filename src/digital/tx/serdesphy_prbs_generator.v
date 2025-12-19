/*
 * SerDes PHY PRBS Generator
 * PRBS-7 pattern generator (x^7 + x^6 + 1)
 * Output width: 8 bits parallel
 * Update rate: 24 MHz
 */

`default_nettype none

module serdesphy_prbs_generator (
    // Clock and reset
    input  wire        clk,            // 24 MHz clock
    input  wire        rst_n,          // Active-low reset
    
    // Control signals
    input  wire        enable,         // Enable PRBS generator
    input  wire        reset_pattern,   // Reset pattern to initial state
    
    // Output interface
    output wire [7:0]  prbs_data,      // 8-bit PRBS output
    output wire        prbs_valid,     // PRBS data valid
    input  wire        prbs_ready      // Ready for next PRBS word
);

    // Internal registers
    reg [6:0] prbs_shift_reg;  // 7-bit LFSR
    reg [7:0] output_data_reg;
    reg        output_valid_reg;
    reg [1:0] generator_state;
    
    // State encoding
    localparam STATE_IDLE    = 2'b00;
    localparam STATE_GENERATE = 2'b01;
    localparam STATE_READY   = 2'b10;
    localparam STATE_OUTPUT  = 2'b11;
    
    // PRBS-7 LFSR polynomial: x^7 + x^6 + 1
    // Feedback: bit 6 XOR bit 5 (using 0-based indexing)
    function [6:0] lfsr_next;
        input [6:0] current_state;
        begin
            lfsr_next = {current_state[5:0], 
                        current_state[6] ^ current_state[5]};
        end
    endfunction
    
    // Generate 8-bit PRBS sequence
    function [7:0] generate_8bit_prbs;
        input [6:0] initial_state;
        reg [6:0] temp_state;
        integer i;
        begin
            temp_state = initial_state;
            generate_8bit_prbs = 8'b0;
            
            for (i = 0; i < 8; i = i + 1) begin
                generate_8bit_prbs[i] = temp_state[6];  // Output MSB
                temp_state = lfsr_next(temp_state);
            end
        end
    endfunction
    
    // PRBS generator state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            generator_state <= STATE_IDLE;
            prbs_shift_reg <= 7'h7F;  // Non-zero initial state
            output_data_reg <= 8'h00;
            output_valid_reg <= 0;
        end else if (reset_pattern) begin
            generator_state <= STATE_IDLE;
            prbs_shift_reg <= 7'h7F;  // Reset to known state
            output_data_reg <= 8'h00;
            output_valid_reg <= 0;
        end else if (!enable) begin
            generator_state <= STATE_IDLE;
            output_valid_reg <= 0;
        end else begin
            case (generator_state)
                STATE_IDLE: begin
                    output_valid_reg <= 0;
                    if (prbs_ready) begin
                        generator_state <= STATE_GENERATE;
                    end
                end
                
                STATE_GENERATE: begin
                    // Generate 8-bit PRBS sequence
                    output_data_reg <= generate_8bit_prbs(prbs_shift_reg);
                    // Update LFSR state for next cycle
                    prbs_shift_reg <= generate_8bit_prbs(prbs_shift_reg);
                    generator_state <= STATE_READY;
                end
                
                STATE_READY: begin
                    output_valid_reg <= 1;
                    generator_state <= STATE_OUTPUT;
                end
                
                STATE_OUTPUT: begin
                    if (prbs_ready) begin
                        output_valid_reg <= 0;
                        generator_state <= STATE_GENERATE;
                    end else begin
                        generator_state <= STATE_IDLE;
                    end
                end
                
                default: begin
                    generator_state <= STATE_IDLE;
                end
            endcase
        end
    end
    
    // Output assignments
    assign prbs_data = output_data_reg;
    assign prbs_valid = output_valid_reg;

endmodule