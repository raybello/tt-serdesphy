/*
 * SerDes PHY Word Assembler — DDR input
 *
 * Combines two 4-bit nibbles into one 8-bit word per clock cycle using
 * double-data-rate sampling:
 *   rising edge  → low nibble  (tx_data_nibble[3:0])
 *   falling edge → high nibble (tx_data_nibble[3:0])
 *
 * Latency: 1 posedge cycle from tx_valid assertion to tx_word_valid.
 * The module is always ready; tx_word_ready is permanently asserted.
 */

`default_nettype none

module serdesphy_word_assembler (
    input  wire       clk,             // 24 MHz clock
    input  wire       rst_n,           // Active-low reset

    // DDR input interface
    input  wire [3:0] tx_data_nibble,  // 4-bit nibble; low on rising, high on falling edge
    input  wire       tx_valid,        // Rising-edge strobe: one DDR pair is on the bus

    // 8-bit output
    output wire [7:0] tx_data_word,    // {high_nibble, low_nibble}
    output wire       tx_word_valid,   // Asserted one cycle after tx_valid
    output wire       tx_word_ready    // Always 1 — 1 word assembled per DDR cycle
);

    // -------------------------------------------------------------------------
    // Falling-edge capture — grabs the high nibble
    // -------------------------------------------------------------------------
    reg [3:0] nibble_fall_r;

    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) nibble_fall_r <= 4'h0;
        else        nibble_fall_r <= tx_data_nibble;
    end

    // -------------------------------------------------------------------------
    // Rising-edge registration
    //   nibble_low_r  : low nibble sampled at posedge (same edge as tx_valid)
    //   nibble_high_r : re-synchronises nibble_fall_r into the posedge domain
    //   word_valid_reg: 1-cycle delayed tx_valid
    // -------------------------------------------------------------------------
    reg [3:0] nibble_low_r;
    reg [3:0] nibble_high_r;
    reg       word_valid_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nibble_low_r   <= 4'h0;
            nibble_high_r  <= 4'h0;
            word_valid_reg <= 1'b0;
        end else begin
            nibble_low_r   <= tx_data_nibble;  // low nibble: captured at this posedge
            nibble_high_r  <= nibble_fall_r;   // high nibble: negedge value, now posedge-safe
            word_valid_reg <= tx_valid;
        end
    end

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------
    assign tx_data_word  = {nibble_high_r, nibble_low_r};
    assign tx_word_valid = word_valid_reg;
    assign tx_word_ready = 1'b1;  // 1 word per DDR cycle — always ready

endmodule

`default_nettype wire
