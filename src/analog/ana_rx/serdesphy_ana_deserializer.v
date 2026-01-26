/*
 * SerDes PHY Analog Deserializer
 * Behavioral RTL model - 1:16 serial-to-parallel converter
 *
 * Operation:
 *   1. Shift in serial data at 240 MHz clock rate
 *   2. After 16 bits collected, pulse data_valid=1 for one cycle
 *   3. Output 16-bit parallel word on parallel_out
 *   4. Continuously shift - no explicit load control needed
 *
 * Timing:
 *   - 16-bit word takes 16 clocks at 240 MHz = 66.67 ns
 *   - data_valid pulses every 16 clocks when enabled
 */

`default_nettype none

module serdesphy_ana_deserializer (
    // Clock and reset
    input  wire       clk_240m_rx,    // 240 MHz recovered clock
    input  wire       rst_n,          // Active-low reset

    // Control signals
    input  wire       enable,         // Enable deserializer

    // Data interface
    input  wire       serial_in,      // Serial data input
    output wire [15:0] parallel_out,  // 16-bit parallel data out
    output wire       data_valid,     // 16-bit data valid (pulse)
    output wire       busy            // Deserializer busy flag
);

    // Internal state
    reg [15:0] shift_reg;
    reg [3:0]  bit_counter;
    reg [15:0] parallel_out_reg;
    reg        data_valid_reg;
    reg        busy_reg;

    // Deserializer shift register
    always @(posedge clk_240m_rx or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 16'h0000;
            bit_counter <= 4'd0;
            parallel_out_reg <= 16'h0000;
            data_valid_reg <= 1'b0;
            busy_reg <= 1'b0;
        end else if (!enable) begin
            // Disabled - reset state
            shift_reg <= 16'h0000;
            bit_counter <= 4'd0;
            data_valid_reg <= 1'b0;
            busy_reg <= 1'b0;
            // Keep last valid output
        end else begin
            // Shift in serial data (MSB first)
            shift_reg <= {shift_reg[14:0], serial_in};
            busy_reg <= 1'b1;

            if (bit_counter == 4'd15) begin
                // 16 bits collected - output word and pulse valid
                parallel_out_reg <= {shift_reg[14:0], serial_in};
                data_valid_reg <= 1'b1;
                bit_counter <= 4'd0;
            end else begin
                bit_counter <= bit_counter + 1;
                data_valid_reg <= 1'b0;
            end
        end
    end

    // Output assignments
    assign parallel_out = parallel_out_reg;
    assign data_valid = data_valid_reg;
    assign busy = busy_reg;

endmodule