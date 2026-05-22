/*
 * SerDes PHY Manchester Encoder
 * Converts 8-bit parallel to 16-bit biphase code
 * Logic 0: High-to-Low transition at bit center
 * Logic 1: Low-to-High transition at bit center
 */

`default_nettype none

module serdesphy_manchester_encoder (
    // Clock and reset
    input  wire        clk,            // 24 MHz clock
    input  wire        rst_n,          // Active-low reset
    
    // Input interface
    input  wire [7:0]  data_in,        // 8-bit parallel data
    input  wire        data_valid,      // Input data valid
    
    // Output interface (to serializer)
    output wire [15:0] manchester_data, // 16-bit Manchester encoded data
    output wire        manchester_valid, // Output data valid
    input  wire        serializer_ready // Ready for next encoded word
);

    // Internal registers
    reg [7:0]  input_data_reg;
    reg [15:0] encoded_data_reg;
    reg         input_valid_reg;
    reg         output_valid_reg;
    reg [1:0]  encode_state;
    
    // State encoding
    localparam STATE_IDLE       = 2'b00;
    localparam STATE_ENCODING    = 2'b01;
    localparam STATE_READY      = 2'b10;
    localparam STATE_OUTPUT     = 2'b11;
    
    // State machine for encoding process
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            encode_state <= STATE_IDLE;
            input_data_reg <= 8'h00;
            encoded_data_reg <= 16'h0000;
            input_valid_reg <= 0;
            output_valid_reg <= 0;
        end else begin
            case (encode_state)
                STATE_IDLE: begin
                    output_valid_reg <= 0;
                    if (data_valid) begin
                        input_data_reg <= data_in;
                        input_valid_reg <= 1;
                        encode_state <= STATE_ENCODING;
                    end
                end
                
                STATE_ENCODING: begin
                    // Logic 0 → 10 (High-to-Low), Logic 1 → 01 (Low-to-High)
                    encoded_data_reg <= {
                        input_data_reg[7] ? 2'b01 : 2'b10,
                        input_data_reg[6] ? 2'b01 : 2'b10,
                        input_data_reg[5] ? 2'b01 : 2'b10,
                        input_data_reg[4] ? 2'b01 : 2'b10,
                        input_data_reg[3] ? 2'b01 : 2'b10,
                        input_data_reg[2] ? 2'b01 : 2'b10,
                        input_data_reg[1] ? 2'b01 : 2'b10,
                        input_data_reg[0] ? 2'b01 : 2'b10
                    };
                    encode_state <= STATE_READY;
                end
                
                STATE_READY: begin
                    output_valid_reg <= 1;
                    encode_state <= STATE_OUTPUT;
                end
                
                STATE_OUTPUT: begin
                    if (serializer_ready) begin
                        output_valid_reg <= 0;
                        input_valid_reg <= 0;
                        encode_state <= STATE_IDLE;
                    end
                end
                
                default: begin
                    encode_state <= STATE_IDLE;
                end
            endcase
        end
    end
    
    // Output assignments
    assign manchester_data = encoded_data_reg;
    assign manchester_valid = output_valid_reg;

endmodule