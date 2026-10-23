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
    input  wire [3:0] csr_vco_trim,    // VCO trim from CSR (manual mode)
    input  wire       cal_enable,      // Enable automatic calibration (default 1'b0 for backward compat)

    // Loop filter status for calibration
    input  wire [7:0] loop_filter_out, // Loop filter output (default 8'h80 for backward compat)

    // Status from analog PLL (PMA)
    input  wire       pll_lock_raw,    // Raw PLL lock from analog
    input  wire       pll_vco_ok,      // VCO operating range indicator
    input  wire       pll_cp_ok,       // Charge pump OK indicator

    // Qualified status outputs
    output wire       pll_lock,        // Validated PLL lock
    output wire       pll_ready,       // PLL ready for operation
    output wire [7:0] pll_status,      // Diagnostic status word
    output wire       pll_error,       // PLL error flag (always 0 - see header)

    // VCO trim output (calibrated or CSR pass-through)
    output wire [3:0] vco_trim_out,    // VCO trim to analog PLL
    output wire       cal_done,        // Calibration complete flag
    output wire       cal_active       // Calibration in progress
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

    // Loop filter frequency lock range - for 200ppm jitter spec
    // Loop filter centered at 128 indicates zero frequency error
    // Tight range around center ensures frequency within spec
    // ±16 from center = ±5 MHz = ±2% of 240 MHz (tighter than ±17% with full range)
    localparam LOOP_LOCK_MIN = 8'd112;  // 128 - 16
    localparam LOOP_LOCK_MAX = 8'd144;  // 128 + 16

    localparam [1:0]
        LOCK_STATE_UNLOCKED  = 2'b00,
        LOCK_STATE_ACQUIRING = 2'b01,
        LOCK_STATE_LOCKED    = 2'b10;

    reg [1:0]  lock_state;
    reg [15:0] lock_counter;
    reg [15:0] unlock_counter;
    reg        pll_lock_reg;
    reg        pll_ready_reg;

    // PLL is healthy when loop filter is in lock range (not saturated)
    // This ensures frequency is within 200ppm spec before declaring lock
    wire loop_in_range = (loop_filter_out >= LOOP_LOCK_MIN) &&
                         (loop_filter_out <= LOOP_LOCK_MAX);
    wire pll_healthy = phy_en && pll_lock_raw && pll_vco_ok && pll_cp_ok && loop_in_range;

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

    // =========================================================================
    // PLL Calibration - Binary Search on VCO Trim
    // =========================================================================

    // Calibration FSM states
    localparam [2:0]
        CAL_IDLE        = 3'b000,
        CAL_INIT        = 3'b001,
        CAL_WAIT_SETTLE = 3'b010,
        CAL_CHECK_LOCK  = 3'b011,
        CAL_UPDATE      = 3'b100,
        CAL_DONE        = 3'b101;

    // Calibration timing parameters
    localparam CAL_SETTLE_CYCLES = 16'd4800;   // 200us @ 24MHz for PLL loop startup + settle
    localparam CAL_LOCK_CHECK_CYCLES = 16'd240; // 10us @ 24MHz to confirm lock
    localparam MAX_CAL_ITERATIONS = 4'd8;      // Max iterations for binary search

    // Loop filter saturation thresholds for calibration
    // Use same thresholds as lock detection to ensure proper frequency
    // If loop filter is outside [112:144], VCO trim needs adjustment
    localparam LOOP_SAT_HIGH = 8'd160;  // Above this: VCO too slow, need higher trim
    localparam LOOP_SAT_LOW  = 8'd96;   // Below this: VCO too fast, need lower trim

    // Calibration registers
    reg [2:0]  cal_state;
    reg [3:0]  vco_trim_cal;
    reg [3:0]  search_min;
    reg [3:0]  search_max;
    reg [15:0] cal_timer;
    reg        cal_done_reg;
    reg [3:0]  cal_iteration;
    reg        pll_cp_ok_prev;    // Track PLL enable transitions
    reg        pll_lock_raw_prev;  // Track PLL lock transitions

    // Calibration FSM
    always @(posedge clk_ref_24m or negedge rst_n) begin
        if (!rst_n) begin
            cal_state     <= CAL_IDLE;
            vco_trim_cal  <= 4'h8;  // Default on reset
            search_min    <= 4'h0;
            search_max    <= 4'hF;
            cal_timer     <= 16'd0;
            cal_done_reg  <= 1'b0;
            cal_iteration <= 4'd0;
            pll_cp_ok_prev <= 1'b0;
            pll_lock_raw_prev <= 1'b0;
        end else begin
            // Track transitions to detect when PLL is disabled/reset
            pll_cp_ok_prev <= pll_cp_ok;
            pll_lock_raw_prev <= pll_lock_raw;

            // Clear cal_done on falling edge of pll_cp_ok or pll_lock_raw
            // (allows recalibration after PLL disable or pll_rst)
            if ((pll_cp_ok_prev && !pll_cp_ok) ||  // PLL disabled
                (pll_lock_raw_prev && !pll_lock_raw)) begin  // PLL reset or lost lock
                cal_done_reg <= 1'b0;
`ifndef SYNTHESIS
                $display("[CAL] @ %0.3f us: EDGE DETECT cleared cal_done_reg (pll_cp_ok: %0b->%0b, pll_lock_raw: %0b->%0b)",
                         $realtime/1000000.0, pll_cp_ok_prev, pll_cp_ok, pll_lock_raw_prev, pll_lock_raw);
`endif
            end

            case (cal_state)
                CAL_IDLE: begin
                    if (cal_enable && phy_en && !cal_done_reg && pll_cp_ok) begin
                        // Start calibration - use CSR value as first try
                        vco_trim_cal  <= csr_vco_trim;
                        cal_state     <= CAL_WAIT_SETTLE;  // Skip INIT, go directly to settle
                        cal_timer     <= 16'd0;
                        search_min    <= 4'h0;
                        search_max    <= 4'hF;
                        cal_iteration <= 4'd0;
`ifndef SYNTHESIS
                        $display("[CAL] @ %0.3f us: START calibration from CSR trim=%0d, pll_cp_ok=%0b",
                                 $realtime/1000000.0, csr_vco_trim, pll_cp_ok);
`endif
                    end else if (!cal_enable) begin
                        // Pass through CSR value in manual mode
                        vco_trim_cal <= csr_vco_trim;
                    end
                end

                CAL_INIT: begin
                    // Calculate and apply midpoint for binary search
                    vco_trim_cal <= (search_min + search_max) >> 1;
                    cal_timer    <= 16'd0;
                    cal_state    <= CAL_WAIT_SETTLE;
`ifndef SYNTHESIS
                    $display("[CAL] @ %0.3f us: INIT iter=%0d, trying trim=%0d, range=[%0d:%0d]",
                             $realtime/1000000.0, cal_iteration, (search_min + search_max) >> 1,
                             search_min, search_max);
`endif
                end

                CAL_WAIT_SETTLE: begin
                    // Wait for PLL to settle with new vco_trim
                    if (cal_timer < CAL_SETTLE_CYCLES) begin
                        cal_timer <= cal_timer + 1;
                    end else begin
                        cal_timer <= 16'd0;
                        cal_state <= CAL_CHECK_LOCK;
`ifndef SYNTHESIS
                        $display("[CAL] @ %0.3f us: SETTLE done, checking lock (trim=%0d, loop_filter=%0d)",
                                 $realtime/1000000.0, vco_trim_cal, loop_filter_out);
`endif
                    end
                end

                CAL_CHECK_LOCK: begin
                    // Check if PLL achieved lock
                    if (pll_lock_reg) begin
                        // Locked! Calibration successful
                        cal_state    <= CAL_DONE;
                        cal_done_reg <= 1'b1;  // Set when transitioning to DONE
`ifndef SYNTHESIS
                        $display("[CAL] @ %0.3f us: LOCKED! Final trim=%0d", $realtime/1000000.0, vco_trim_cal);
`endif
                    end else if (cal_timer < CAL_LOCK_CHECK_CYCLES) begin
                        cal_timer <= cal_timer + 1;
                    end else begin
                        cal_state <= CAL_UPDATE;
`ifndef SYNTHESIS
                        $display("[CAL] @ %0.3f us: NO LOCK, updating search (loop_filter=%0d)",
                                 $realtime/1000000.0, loop_filter_out);
`endif
                    end
                end

                CAL_UPDATE: begin
                    cal_iteration <= cal_iteration + 1;

                    // Check if converged or max iterations reached
                    if ((search_max <= search_min + 1) ||
                        (cal_iteration >= MAX_CAL_ITERATIONS)) begin
                        // Done - use current value
                        cal_state    <= CAL_DONE;
                        cal_done_reg <= 1'b1;  // Set when transitioning to DONE
`ifndef SYNTHESIS
                        $display("[CAL] @ %0.3f us: DONE (converged or max iter), final trim=%0d",
                                 $realtime/1000000.0, vco_trim_cal);
`endif
                    end else begin
                        // Determine search direction based on loop filter position
                        // For 200ppm lock requirement, we need loop filter near 128

                        if (loop_filter_out > LOOP_SAT_HIGH) begin
                            // Loop filter saturated high (>160) -> VCO too slow
                            // Need higher frequency -> increase vco_trim
                            search_min <= vco_trim_cal + 1;
`ifndef SYNTHESIS
                            $display("[CAL] @ %0.3f us: UPDATE loop=%0d >%0d SAT_HIGH, search_min: %0d -> %0d",
                                     $realtime/1000000.0, loop_filter_out, LOOP_SAT_HIGH,
                                     search_min, vco_trim_cal + 1);
`endif
                        end else if (loop_filter_out < LOOP_SAT_LOW) begin
                            // Loop filter saturated low (<96) -> VCO too fast
                            // Need lower frequency -> decrease vco_trim
                            search_max <= vco_trim_cal - 1;
`ifndef SYNTHESIS
                            $display("[CAL] @ %0.3f us: UPDATE loop=%0d <%0d SAT_LOW, search_max: %0d -> %0d",
                                     $realtime/1000000.0, loop_filter_out, LOOP_SAT_LOW,
                                     search_max, vco_trim_cal - 1);
`endif
                        end else if (loop_filter_out >= 8'd128) begin
                            // Loop filter at or above center (128-160) -> VCO slow or nominal
                            // Need higher frequency -> increase vco_trim
                            search_min <= vco_trim_cal + 1;
`ifndef SYNTHESIS
                            $display("[CAL] @ %0.3f us: UPDATE loop=%0d >=128 (slow/nominal), search_min: %0d -> %0d",
                                     $realtime/1000000.0, loop_filter_out, search_min, vco_trim_cal + 1);
`endif
                        end else begin
                            // Loop filter below center (96-127) -> VCO slightly fast
                            // Need lower frequency -> decrease vco_trim
                            search_max <= vco_trim_cal - 1;
`ifndef SYNTHESIS
                            $display("[CAL] @ %0.3f us: UPDATE loop=%0d <128 (fast), search_max: %0d -> %0d",
                                     $realtime/1000000.0, loop_filter_out, search_max, vco_trim_cal - 1);
`endif
                        end
                        cal_state <= CAL_INIT;
                    end
                end

                CAL_DONE: begin
                    // Hold in done state - cal_done_reg was already set when entering
                    // Return to IDLE if disabled OR if cal_done_reg was cleared (by edge detection)
                    if (!cal_enable || !phy_en || !cal_done_reg) begin
                        cal_state <= CAL_IDLE;
`ifndef SYNTHESIS
                        $display("[CAL] @ %0.3f us: Exiting DONE to IDLE (cal_enable=%0b, phy_en=%0b, cal_done_reg=%0b)",
                                 $realtime/1000000.0, cal_enable, phy_en, cal_done_reg);
`endif
                    end
                end

                default: begin
                    cal_state <= CAL_IDLE;
                end
            endcase
        end
    end

    // Output assignments for calibration
    assign vco_trim_out = cal_enable ? vco_trim_cal : csr_vco_trim;
    assign cal_done     = cal_done_reg;
    assign cal_active   = (cal_state != CAL_IDLE) && (cal_state != CAL_DONE);

endmodule
