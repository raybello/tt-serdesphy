/*
 * SerDes PHY PLL Lock Qualifier
 *
 * Computes PLL_LOCK/PLL_READY from the analog PLL's raw status
 * (pll_lock_raw/pll_vco_ok/pll_cp_ok), independent of any other PHY block's
 * enable state (in particular: independent of TX_EN/serializer_enable -
 * see docs/implementation/01-spec-vs-implementation.md Finding 2.1, which
 * this module fixes. STATUS[0] previously aliased the TX serializer's
 * "ready" signal, so polling PLL_LOCK before enabling TX - exactly what
 * docs/info.md section 8.1's own init sequence does - could never see it
 * assert).
 *
 * Adds hysteresis on top of the raw lock signal: LOCK_COUNT_MAX cycles of
 * continuous raw lock before claiming PLL_LOCK, UNLOCK_COUNT cycles of
 * continuous raw unlock before dropping it, so brief glitches on the
 * analog side don't bounce the status bit.
 *
 * No independent PLL_ERROR is derived here: in the current PMA
 * (src/analog/serdesphy_pma.v), pll_vco_ok is simply
 * `assign pll_vco_ok = pll_lock_raw;` - i.e. not an independent
 * "VCO in operating range" signal, just an alias of pll_lock_raw itself.
 * An earlier version of this module treated `phy_en && !pll_vco_ok` as an
 * error condition, which is true for the entire ~10us acquisition window
 * every time the PLL starts up (pll_lock_raw, and therefore pll_vco_ok,
 * is 0 for that whole window by design) - it latched a permanent false
 * "error" before the PLL ever got a chance to lock. Once the PMA exposes
 * a real, independent VCO/charge-pump health signal (see
 * docs/implementation/pll/README.md's circuit-level plan), this module
 * should grow a real fault path back.
 */

`default_nettype none

module serdesphy_pll_ctrl (
    // Clock and reset
    input  wire       clk_ref_24m,     // 24 MHz reference clock
    input  wire       rst_n,           // Active-low reset

    // Control input from CSR
    input  wire       phy_en,          // PHY global enable

    // Status from analog PLL (PMA)
    input  wire       pll_lock_raw,    // Raw PLL lock from analog
    input  wire       pll_vco_ok,      // VCO operating range indicator
    input  wire       pll_cp_ok,       // Charge pump OK indicator

    // Qualified status outputs
    output wire       pll_lock,        // Validated PLL lock
    output wire       pll_ready,       // PLL ready for operation
    output wire [7:0] pll_status,      // Diagnostic status word
    output wire       pll_error        // PLL error flag (always 0 - see header)
);

    // docs/info.md 4.1 PLL lock time is 8-10us typ/max, and
    // serdesphy_ana_pll.v's own STATE_ACQUIRE already spends the full
    // 240 cycles (10us @ 24MHz) getting pll_lock_raw to assert in the
    // first place - pll_lock_raw is a clean, debounced FSM output, not
    // a noisy comparator, so this stage only needs a handful of cycles
    // of extra debounce on top of that, not another full acquisition
    // wait.
    localparam LOCK_COUNT_MAX = 16'd4;     // ~167ns extra debounce @ 24MHz
    localparam UNLOCK_COUNT   = 16'd240;   // 10us before unlock declaration

    localparam [1:0]
        LOCK_STATE_UNLOCKED  = 2'b00,
        LOCK_STATE_ACQUIRING = 2'b01,
        LOCK_STATE_LOCKED    = 2'b10;

    reg [1:0]  lock_state;
    reg [15:0] lock_counter;
    reg [15:0] unlock_counter;
    reg        pll_lock_reg;
    reg        pll_ready_reg;

    wire pll_healthy = phy_en && pll_lock_raw && pll_vco_ok && pll_cp_ok;

    always @(posedge clk_ref_24m or negedge rst_n) begin
        if (!rst_n) begin
            lock_state     <= LOCK_STATE_UNLOCKED;
            lock_counter   <= 16'd0;
            unlock_counter <= 16'd0;
            pll_lock_reg   <= 1'b0;
            pll_ready_reg  <= 1'b0;
        end else begin
            case (lock_state)
                LOCK_STATE_UNLOCKED: begin
                    if (pll_healthy) begin
                        lock_state     <= LOCK_STATE_ACQUIRING;
                        lock_counter   <= 16'd0;
                        unlock_counter <= 16'd0;
                    end
                end

                LOCK_STATE_ACQUIRING: begin
                    if (pll_healthy) begin
                        if (lock_counter < LOCK_COUNT_MAX) begin
                            lock_counter <= lock_counter + 1;
                        end else begin
                            lock_state    <= LOCK_STATE_LOCKED;
                            pll_lock_reg  <= 1'b1;
                            pll_ready_reg <= 1'b1;
                        end
                    end else begin
                        lock_state     <= LOCK_STATE_UNLOCKED;
                        lock_counter   <= 16'd0;
                        unlock_counter <= 16'd0;
                    end
                end

                LOCK_STATE_LOCKED: begin
                    if (!phy_en) begin
                        lock_state    <= LOCK_STATE_UNLOCKED;
                        pll_lock_reg  <= 1'b0;
                        pll_ready_reg <= 1'b0;
                    end else if (!pll_healthy) begin
                        if (unlock_counter < UNLOCK_COUNT) begin
                            unlock_counter <= unlock_counter + 1;
                        end else begin
                            lock_state     <= LOCK_STATE_UNLOCKED;
                            pll_lock_reg   <= 1'b0;
                            pll_ready_reg  <= 1'b0;
                            unlock_counter <= 16'd0;
                        end
                    end else begin
                        unlock_counter <= 16'd0;
                    end
                end

                default: begin
                    lock_state <= LOCK_STATE_UNLOCKED;
                end
            endcase
        end
    end

    assign pll_lock   = pll_lock_reg;
    assign pll_ready  = pll_ready_reg;
    assign pll_error  = 1'b0;
    assign pll_status = {4'b0000, pll_cp_ok, pll_vco_ok, pll_lock_raw, phy_en};

endmodule
