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
    
    // PRBS-7 byte-wide advance: applies the x^7+x^6+1 Fibonacci LFSR
    // recurrence (fb = s[6]^s[5]; s <= {s[5:0], fb}) 8 times per call, MSB
    // of the output byte first. The previous version only computed a
    // correct feedback bit for bit 7 and then just copied the other 7
    // register bits through unshifted for bits 6..0 - starting from the
    // reset state 7'h7F (all ones), reordering all-1 bits yields all-1
    // bits again, so that formula was a genuine fixed point: the LFSR
    // could never leave 7F, making "PRBS" mode transmit a constant,
    // perfectly periodic byte forever instead of a pseudorandom sequence.
    function automatic [14:0] prbs7_advance_byte;
        input [6:0] state;
        integer i;
        reg [6:0] s;
        reg [7:0] b;
        reg        fb;
        begin
            s = state;
            for (i = 0; i < 8; i = i + 1) begin
                fb = s[6] ^ s[5];
                b[7-i] = fb;
                s = {s[5:0], fb};
            end
            prbs7_advance_byte = {s, b};
        end
    endfunction

    wire [14:0] prbs7_result     = prbs7_advance_byte(prbs_shift_reg);
    wire [7:0]  prbs_next_byte   = prbs7_result[7:0];
    wire [6:0]  prbs_next_state  = prbs7_result[14:8];

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
                    // Hold here (output_valid_reg stays 1, data stays
                    // stable) until the consumer is actually ready -
                    // never fall through to STATE_IDLE while a byte is
                    // still waiting to be captured. STATE_IDLE
                    // unconditionally clears output_valid_reg the very
                    // next cycle regardless of prbs_ready, which used to
                    // make this exact "not ready THIS cycle" branch
                    // silently discard the current byte forever the
                    // instant serdesphy_tx_data_mux.v's own multi-cycle
                    // capture sequence hadn't caught up yet - roughly
                    // every other byte was lost this way whenever the
                    // mux's round trip took longer than one cycle to get
                    // back to waiting (which it always does - see
                    // serdesphy_tx_data_mux.v's STATE_SELECT/OUTPUT/
                    // STATE_READY sequence), confirmed by a cycle-by-cycle
                    // trace showing a byte visibly presented with valid=1
                    // and then cleared to 0 one cycle later with
                    // mux_valid never having pulsed for it at all.
                    if (prbs_ready) begin
                        output_valid_reg <= 0;
                        generator_state <= STATE_GENERATE;
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