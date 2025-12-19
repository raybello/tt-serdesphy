/*
 * SerDes PHY Manchester Decoder
 * Biphase to 8-bit parallel conversion
 * Logic 0: High-to-Low transition at bit center
 * Logic 1: Low-to-High transition at bit center
 */

`default_nettype none

module serdesphy_manchester_decoder (
    // Clock and reset
    input  wire        clk,            // 24 MHz clock
    input  wire        rst_n,          // Active-low reset
    
    // Input interface (from deserializer)
    input  wire [15:0] manchester_data, // 16-bit Manchester encoded data
    input  wire        data_valid,      // Input data valid
    
    // Output interface
    output wire [7:0]  decoded_data,    // 8-bit decoded data
    output wire        decode_valid,    // Output data valid
    output wire        decode_error     // Manchester error detected
);

    // Internal registers
    reg [15:0] manchester_data_reg;
    reg         data_valid_reg;
    reg [7:0]  decoded_data_reg;
    reg         decode_valid_reg;
    reg         error_reg;
    reg [1:0]  decode_state;
    
    // State encoding
    localparam STATE_IDLE      = 2'b00;
    localparam STATE_DECODING   = 2'b01;
    localparam STATE_READY     = 2'b10;
    localparam STATE_OUTPUT    = 2'b11;
    
    // Manchester decoding logic
    function [7:0] decode_manchester;
        input [15:0] data;
        input error_detected;
        integer i;
        begin
            error_detected = 0;
            decode_manchester = 8'b0;
            
            for (i = 0; i < 8; i = i + 1) begin
                // Extract 2-bit symbol pair
                case ({data[2*i+1], data[2*i]})  // MSB first
                    2'b10: begin
                        // High-to-Low transition = Logic 0 (valid)
                        decode_manchester[i] = 1'b0;
                    end
                    2'b01: begin
                        // Low-to-High transition = Logic 1 (valid)
                        decode_manchester[i] = 1'b1;
                    end
                    default: begin
                        // Invalid Manchester pattern
                        error_detected = 1;
                    end
                endcase
            end
        end
    endfunction
    
    // State machine for decoding process
    reg manchester_error_flag;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            decode_state <= STATE_IDLE;
            manchester_data_reg <= 16'h0000;
            data_valid_reg <= 0;
            decoded_data_reg <= 8'h00;
            decode_valid_reg <= 0;
            error_reg <= 0;
            manchester_error_flag <= 0;
        end else begin
            case (decode_state)
                STATE_IDLE: begin
                    decode_valid_reg <= 0;
                    error_reg <= 0;
                    if (data_valid) begin
                        manchester_data_reg <= manchester_data;
                        data_valid_reg <= 1;
                        decode_state <= STATE_DECODING;
                    end
                end
                
                STATE_DECODING: begin
                    // Perform Manchester decoding
                    reg [7:0] temp_data;
                    reg temp_error;
                    
                    {temp_data, temp_error} = decode_manchester(manchester_data_reg);
                    decoded_data_reg <= temp_data;
                    manchester_error_flag <= temp_error;
                    decode_state <= STATE_READY;
                end
                
                STATE_READY: begin
                    decode_valid_reg <= 1;
                    if (manchester_error_flag) begin
                        error_reg <= 1;
                    end
                    decode_state <= STATE_OUTPUT;
                end
                
                STATE_OUTPUT: begin
                    decode_valid_reg <= 0;
                    data_valid_reg <= 0;
                    decode_state <= STATE_IDLE;
                end
                
                default: begin
                    decode_state <= STATE_IDLE;
                end
            endcase
        end
    end
    
    // Output assignments
    assign decoded_data = decoded_data_reg;
    assign decode_valid = decode_valid_reg;
    assign decode_error = error_reg;

endmodule