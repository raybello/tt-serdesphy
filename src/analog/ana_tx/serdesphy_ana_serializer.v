/*
 * SerDes PHY Analog Serializer
 * Behavioral RTL model - 16:1 parallel-to-serial converter
 *
 * Operation:
 *   1. When data_ready=1 and load_data pulse received, load parallel_in
 *   2. Shift out MSB-first at 240 MHz clock rate
 *   3. Assert busy=1 while shifting (16 clock cycles)
 *   4. Assert data_ready=1 when shift complete, ready for next word
 *
 * Timing:
 *   - 16-bit word takes 16 clocks at 240 MHz = 66.67 ns
 *   - Effective data rate: 240 Mbps serial, 15 MHz word rate
 */

`default_nettype none

module serdesphy_ana_serializer (
    // Clock and reset
    input  wire        clk_240m,       // 240 MHz transmit clock
    input  wire        rst_n,          // Active-low reset

    // Control signals
    input  wire        enable,         // Enable serializer
    input  wire        load_data,      // Load new 16-bit data (pulse)

    // Data interface
    input  wire [15:0] parallel_in,    // 16-bit parallel data in
    output wire        serial_out,     // Serial data output
    output wire        busy,           // Serializer busy flag
    output wire        data_ready      // Ready for new data
);

    // Internal state
    reg [15:0] shift_reg;
    reg [3:0]  bit_counter;
    reg        serial_out_reg;
    reg        busy_reg;
    reg        data_ready_reg;
    reg        shifting;

    // Serializer state machine
    always @(posedge clk_240m or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 16'h0000;
            bit_counter <= 4'd0;
            serial_out_reg <= 1'b0;
            busy_reg <= 1'b0;
            data_ready_reg <= 1'b1;
            shifting <= 1'b0;
        end else if (!enable) begin
            // Disabled - reset state but keep outputs stable
            shift_reg <= 16'h0000;
            bit_counter <= 4'd0;
            serial_out_reg <= 1'b0;
            busy_reg <= 1'b0;
            data_ready_reg <= 1'b1;
            shifting <= 1'b0;
        end else begin
            if (load_data && data_ready_reg && !shifting) begin
                // Load new parallel data
                shift_reg <= parallel_in;
                bit_counter <= 4'd15;
                busy_reg <= 1'b1;
                data_ready_reg <= 1'b0;
                shifting <= 1'b1;
                // Output first bit immediately (MSB)
                serial_out_reg <= parallel_in[15];
            end else if (shifting) begin
                // Shift out next bit (MSB first)
                serial_out_reg <= shift_reg[15];
                shift_reg <= {shift_reg[14:0], 1'b0};

                if (bit_counter == 4'd0) begin
                    // Finished shifting all 16 bits
                    busy_reg <= 1'b0;
                    data_ready_reg <= 1'b1;
                    shifting <= 1'b0;
                end else begin
                    bit_counter <= bit_counter - 1;
                end
            end else begin
                // Idle - output low, ready for data
                serial_out_reg <= 1'b0;
            end
        end
    end

    // Output assignments
    assign serial_out = serial_out_reg;
    assign busy = busy_reg;
    assign data_ready = data_ready_reg;

endmodule