/*
 * SerDes PHY Word Disassembler — DDR output
 *
 * Splits one 8-bit received word into two 4-bit nibbles using double-data-rate
 * drive:
 *   rising edge  → rx_data_nibble = word[3:0]  (low nibble)
 *   falling edge → rx_data_nibble = word[7:4]  (high nibble)
 *
 * rx_valid pulses on the rising edge to indicate a new DDR cycle is valid.
 * The host must capture rx_data_nibble on both edges while rx_valid is
 * asserted.
 *
 * Latency: 1 posedge cycle from rx_word_valid to rx_valid.
 * The module is always ready; rx_word_ready is permanently asserted.
 */

`default_nettype none

module serdesphy_word_disassembler (
    input  wire       clk,             // 24 MHz clock
    input  wire       rst_n,           // Active-low reset

    // 8-bit input from RX FIFO
    input  wire [7:0] rx_data_word,    // 8-bit received word
    input  wire       rx_word_valid,   // Word valid strobe

    // DDR output interface
    output wire [3:0] rx_data_nibble,  // Low nibble on rising, high nibble on falling edge
    output wire       rx_valid,        // Rising-edge strobe: DDR cycle is valid
    output wire       rx_word_ready    // Always 1 — 1 word consumed per DDR cycle
);

    // -------------------------------------------------------------------------
    // Rising-edge output register — drives low nibble during clk=1 phase
    // -------------------------------------------------------------------------
    reg [3:0] nibble_rise_out;
    reg       valid_rise;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nibble_rise_out <= 4'h0;
            valid_rise      <= 1'b0;
        end else begin
            nibble_rise_out <= rx_data_word[3:0];
            valid_rise      <= rx_word_valid;
        end
    end

    // -------------------------------------------------------------------------
    // Falling-edge output register — drives high nibble during clk=0 phase
    //
    // rx_data_word is produced by the RX FIFO read side (clk_24m posedge), so
    // it is stable across the entire clock period and safe to sample on negedge.
    // -------------------------------------------------------------------------
    reg [3:0] nibble_fall_out;

    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) nibble_fall_out <= 4'h0;
        else        nibble_fall_out <= rx_data_word[7:4];
    end

    // -------------------------------------------------------------------------
    // DDR output mux
    //   clk=1 (rise phase) → low nibble (registered at previous posedge)
    //   clk=0 (fall phase) → high nibble (registered at this negedge)
    // -------------------------------------------------------------------------
    assign rx_data_nibble = clk ? nibble_rise_out : nibble_fall_out;
    assign rx_valid       = valid_rise;
    assign rx_word_ready  = 1'b1;  // 1 word per DDR cycle — always ready

endmodule

`default_nettype wire
