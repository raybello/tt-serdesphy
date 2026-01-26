/*
 * SerDes PHY Power-On-Reset Controller
 *
 * Simple and robust power-up sequencing:
 * 1. Wait for supplies to stabilize
 * 2. Release isolation, then digital reset, then analog reset
 * 3. Monitor supplies and re-sequence if lost
 */

`default_nettype none

module serdesphy_por (
    // Supply monitoring inputs
    input  wire       dvdd_ok,          // 1.8V digital supply OK
    input  wire       avdd_ok,          // 3.3V analog supply OK

    // External reset and clock
    input  wire       rst_n_in,         // External active-low reset
    input  wire       clk,              // Reference clock (24 MHz)

    // Control inputs
    input  wire       phy_en,           // PHY enable from CSR
    input  wire       iso_en,           // Analog isolation enable from CSR

    // Power sequencing outputs
    output wire       power_good,       // Power supplies stable and ready
    output wire       analog_iso_n,     // Analog isolation control (active-low)
    output wire       digital_reset_n,  // Digital domain reset release
    output wire       analog_reset_n,   // Analog domain reset release

    // Status outputs
    output wire       por_active,       // POR sequence active
    output wire       por_complete      // POR sequence complete
);

    // =========================================================================
    // State Machine Definition (simplified to 4 states)
    // =========================================================================
    localparam [2:0]
        STATE_RESET      = 3'd0,  // Initial reset, all held in reset
        STATE_WAIT_SUPPLY= 3'd1,  // Wait for supplies to stabilize
        STATE_SEQUENCING = 3'd2,  // Release resets in sequence
        STATE_READY      = 3'd3;  // System ready and operational

    // =========================================================================
    // Timing Constants (24 MHz clock = 41.67 ns per cycle)
    // =========================================================================
    localparam [7:0] SUPPLY_STABLE_CYCLES = 8'd48;   // ~2 us for supply debounce
    localparam [7:0] RESET_HOLD_CYCLES    = 8'd24;   // ~1 us reset pulse width
    localparam [7:0] RELEASE_DELAY_CYCLES = 8'd12;   // ~0.5 us between releases

    // Sequencing sub-states (within STATE_SEQUENCING)
    localparam [1:0]
        SEQ_RELEASE_ISO     = 2'd0,
        SEQ_RELEASE_DIGITAL = 2'd1,
        SEQ_RELEASE_ANALOG  = 2'd2,
        SEQ_DONE            = 2'd3;

    // =========================================================================
    // Registers
    // =========================================================================
    reg [2:0]  state;
    reg [1:0]  seq_step;
    reg [7:0]  timer;

    reg        power_good_reg;
    reg        analog_iso_n_reg;
    reg        digital_reset_n_reg;
    reg        analog_reset_n_reg;
    reg        por_complete_reg;

    // =========================================================================
    // Supply Validation
    // =========================================================================
    wire supplies_ok = dvdd_ok && avdd_ok;

    // =========================================================================
    // Main State Machine
    // =========================================================================
    always @(posedge clk or negedge rst_n_in) begin
        if (!rst_n_in) begin
            // Async reset - enter safe state
            state              <= STATE_RESET;
            seq_step           <= SEQ_RELEASE_ISO;
            timer              <= 8'd0;
            power_good_reg     <= 1'b0;
            analog_iso_n_reg   <= 1'b0;   // Start isolated (active-low, so 0 = isolated)
            digital_reset_n_reg<= 1'b0;   // Start in reset
            analog_reset_n_reg <= 1'b0;   // Start in reset
            por_complete_reg   <= 1'b0;
        end else begin
            case (state)
                // -------------------------------------------------------------
                // STATE_RESET: Hold everything in reset, wait for supplies
                // -------------------------------------------------------------
                STATE_RESET: begin
                    power_good_reg     <= 1'b0;
                    analog_iso_n_reg   <= 1'b0;   // Keep isolated
                    digital_reset_n_reg<= 1'b0;   // Keep in reset
                    analog_reset_n_reg <= 1'b0;   // Keep in reset
                    por_complete_reg   <= 1'b0;
                    seq_step           <= SEQ_RELEASE_ISO;

                    if (supplies_ok) begin
                        timer <= SUPPLY_STABLE_CYCLES;
                        state <= STATE_WAIT_SUPPLY;
                    end
                end

                // -------------------------------------------------------------
                // STATE_WAIT_SUPPLY: Debounce supply good signals
                // -------------------------------------------------------------
                STATE_WAIT_SUPPLY: begin
                    if (!supplies_ok) begin
                        // Supply lost - go back to reset
                        state <= STATE_RESET;
                    end else if (timer == 8'd0) begin
                        // Supplies stable - begin sequencing
                        timer <= RELEASE_DELAY_CYCLES;
                        state <= STATE_SEQUENCING;
                    end else begin
                        timer <= timer - 8'd1;
                    end
                end

                // -------------------------------------------------------------
                // STATE_SEQUENCING: Release resets in order
                // -------------------------------------------------------------
                STATE_SEQUENCING: begin
                    if (!supplies_ok) begin
                        // Supply lost during sequencing - abort
                        state <= STATE_RESET;
                    end else if (timer == 8'd0) begin
                        case (seq_step)
                            SEQ_RELEASE_ISO: begin
                                // Release isolation (unless CSR requests it)
                                analog_iso_n_reg <= ~iso_en;
                                timer    <= RESET_HOLD_CYCLES;
                                seq_step <= SEQ_RELEASE_DIGITAL;
                            end

                            SEQ_RELEASE_DIGITAL: begin
                                // Release digital reset
                                digital_reset_n_reg <= 1'b1;
                                timer    <= RELEASE_DELAY_CYCLES;
                                seq_step <= SEQ_RELEASE_ANALOG;
                            end

                            SEQ_RELEASE_ANALOG: begin
                                // Release analog reset
                                analog_reset_n_reg <= 1'b1;
                                timer    <= RELEASE_DELAY_CYCLES;
                                seq_step <= SEQ_DONE;
                            end

                            SEQ_DONE: begin
                                // Sequencing complete
                                power_good_reg   <= 1'b1;
                                por_complete_reg <= 1'b1;
                                state <= STATE_READY;
                            end
                        endcase
                    end else begin
                        timer <= timer - 8'd1;
                    end
                end

                // -------------------------------------------------------------
                // STATE_READY: Normal operation, monitor supplies
                // -------------------------------------------------------------
                STATE_READY: begin
                    por_complete_reg <= 1'b1;
                    power_good_reg   <= supplies_ok;

                    // Update isolation based on CSR setting
                    analog_iso_n_reg <= ~iso_en;

                    // Re-sequence if supplies lost
                    if (!supplies_ok) begin
                        state <= STATE_RESET;
                    end
                end

                // -------------------------------------------------------------
                // Default: Safe fallback to reset
                // -------------------------------------------------------------
                default: begin
                    state <= STATE_RESET;
                end
            endcase
        end
    end

    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign power_good      = power_good_reg;
    assign analog_iso_n    = analog_iso_n_reg;
    assign digital_reset_n = digital_reset_n_reg;
    assign analog_reset_n  = analog_reset_n_reg;
    assign por_active      = (state != STATE_READY);
    assign por_complete    = por_complete_reg;

endmodule