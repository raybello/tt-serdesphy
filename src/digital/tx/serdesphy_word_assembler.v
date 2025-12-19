/*
 * SerDes PHY Word Assembler
 * Combines two 4-bit nibbles into 8-bit words over two CLK_24M cycles
 * Supports TX_VALID gating for 12 MHz effective data rate
 */

`default_nettype none

module serdesphy_word_assembler (
    // Clock and reset
    input  wire       clk,           // 24 MHz clock
    input  wire       rst_n,         // Active-low reset
    
    // Input interface (4-bit external)
    input  wire [3:0] tx_data_nibble, // 4-bit transmit data nibble
    input  wire       tx_valid,        // TX data valid strobe
    
    // Output interface (8-bit internal)
    output wire [7:0] tx_data_word,   // 8-bit assembled word
    output wire       tx_word_valid,   // Word assembled valid
    output wire       tx_word_ready    // Ready for next nibble
);

    // Internal state
    reg [7:0] assembled_word;
    reg [1:0] assembly_state;
    reg       word_valid_reg;
    
    // State encoding
    localparam STATE_WAIT_NIBBLE_0 = 2'b00;
    localparam STATE_WAIT_NIBBLE_1 = 2'b01;
    localparam STATE_WORD_READY    = 2'b10;
    localparam STATE_OUTPUT_WORD    = 2'b11;
    
    // State machine for word assembly
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            assembly_state <= STATE_WAIT_NIBBLE_0;
            assembled_word <= 8'h00;
            word_valid_reg <= 0;
        end else begin
            case (assembly_state)
                STATE_WAIT_NIBBLE_0: begin
                    word_valid_reg <= 0;
                    if (tx_valid) begin
                        assembled_word[3:0] <= tx_data_nibble;  // Lower nibble
                        assembly_state <= STATE_WAIT_NIBBLE_1;
                    end
                end
                
                STATE_WAIT_NIBBLE_1: begin
                    if (tx_valid) begin
                        assembled_word[7:4] <= tx_data_nibble;  // Upper nibble
                        assembly_state <= STATE_WORD_READY;
                    end
                end
                
                STATE_WORD_READY: begin
                    word_valid_reg <= 1;
                    assembly_state <= STATE_OUTPUT_WORD;
                end
                
                STATE_OUTPUT_WORD: begin
                    word_valid_reg <= 0;
                    assembly_state <= STATE_WAIT_NIBBLE_0;
                end
                
                default: begin
                    assembly_state <= STATE_WAIT_NIBBLE_0;
                end
            endcase
        end
    end
    
    // Output assignments
    assign tx_data_word = assembled_word;
    assign tx_word_valid = word_valid_reg;
    assign tx_word_ready = (assembly_state == STATE_WAIT_NIBBLE_0) || 
                         (assembly_state == STATE_WAIT_NIBBLE_1);

endmodule