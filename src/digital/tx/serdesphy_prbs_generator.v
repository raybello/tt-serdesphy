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
    
    // Unrolled PRBS-7 computation from current prbs_shift_reg.
    // Each output bit is the MSB of the LFSR after i steps; the new LFSR
    // state is the lower 7 bits of the 8-bit output (bits [6:0]).
    wire [7:0] prbs_next_byte = {prbs_shift_reg[6] ^ prbs_shift_reg[5],
                                  prbs_shift_reg[0], prbs_shift_reg[1],
                                  prbs_shift_reg[2], prbs_shift_reg[3],
                                  prbs_shift_reg[4], prbs_shift_reg[5],
                                  prbs_shift_reg[6]};
    wire [6:0] prbs_next_state = {prbs_shift_reg[0], prbs_shift_reg[1],
                                   prbs_shift_reg[2], prbs_shift_reg[3],
                                   prbs_shift_reg[4], prbs_shift_reg[5],
                                   prbs_shift_reg[6]};

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
                    output_data_reg <= prbs_next_byte;
                    prbs_shift_reg  <= prbs_next_state;
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