/*
 * SerDes PHY Word Disassembler
 * 8-bit to dual 4-bit output over two cycles
 * Supports RX_VALID for 12 MHz effective data rate
 */

`default_nettype none

module serdesphy_word_disassembler (
    // Clock and reset
    input  wire       clk,           // 24 MHz clock
    input  wire       rst_n,         // Active-low reset
    
    // Input interface (8-bit internal)
    input  wire [7:0] rx_data_word,   // 8-bit received word
    input  wire       rx_word_valid,   // Word received valid
    
    // Output interface (4-bit external)
    output wire [3:0] rx_data_nibble, // 4-bit received data nibble
    output wire       rx_valid,        // RX data valid strobe
    output wire       rx_word_ready    // Ready for next word
);

    // Internal state
    reg [7:0] received_word;
    reg [1:0] disassembly_state;
    reg [3:0] output_nibble;
    reg       valid_reg;
    
    // State encoding
    localparam STATE_WAIT_WORD     = 2'b00;
    localparam STATE_OUTPUT_NIBBLE_0 = 2'b01;
    localparam STATE_OUTPUT_NIBBLE_1 = 2'b10;
    localparam STATE_READY        = 2'b11;
    
    // State machine for word disassembly
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            disassembly_state <= STATE_WAIT_WORD;
            received_word <= 8'h00;
            output_nibble <= 4'h0;
            valid_reg <= 0;
        end else begin
            case (disassembly_state)
                STATE_WAIT_WORD: begin
                    valid_reg <= 0;
                    if (rx_word_valid) begin
                        received_word <= rx_data_word;  // Store 8-bit word
                        output_nibble <= rx_data_word[3:0];  // Lower nibble first
                        valid_reg <= 1;
                        disassembly_state <= STATE_OUTPUT_NIBBLE_0;
                    end
                end
                
                STATE_OUTPUT_NIBBLE_0: begin
                    valid_reg <= 1;
                    output_nibble <= received_word[7:4];  // Upper nibble next
                    disassembly_state <= STATE_OUTPUT_NIBBLE_1;
                end
                
                STATE_OUTPUT_NIBBLE_1: begin
                    valid_reg <= 0;
                    disassembly_state <= STATE_READY;
                end
                
                STATE_READY: begin
                    disassembly_state <= STATE_WAIT_WORD;
                end
                
                default: begin
                    disassembly_state <= STATE_WAIT_WORD;
                end
            endcase
        end
    end
    
    // Output assignments
    assign rx_data_nibble = output_nibble;
    assign rx_valid = valid_reg;
    assign rx_word_ready = (disassembly_state == STATE_WAIT_WORD);

endmodule