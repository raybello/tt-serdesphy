/*
 * SerDes PHY PLL Lock Qualifier and VCO Trim Calibration
 *
 * Lock qualification is derived only from the PLL itself (raw frequency lock +
 * enabled state), independent of TX_EN/serializer state. Hysteresis debounces
 * the raw lock output.
 *
 * Calibration is a closed-loop binary search on the 4-bit VCO trim. It does not
 * trust a lock bit alone: after each trim step it waits for the analog loop to
 * settle, then checks that the loop-filter control is near mid-scale (128).
 * The direction is taken from the control voltage:
 *
 *   control > CENTER + WINDOW  -> VCO is too slow -> increase trim
 *   control < CENTER - WINDOW  -> VCO is too fast -> decrease trim
 *
 * Search bounds are kept in 5-bit arithmetic so the midpoint and the +/-1
 * steps cannot wrap at 0 or 15. Calibration completes when the control is
 * inside the window (and the analog PLL is frequency-locked), when the search
 * interval collapses, or after MAX_ITERATIONS.
 *
 * Timing: CAL_SETTLE_CYCLES = 192 reference cycles (~8 us at 24 MHz), which is
 * enough for the behavioral loop to acquire from any trim. Default trim 0x8
 * normally completes in the first check; extreme trims take at most 4 steps.
 */

`default_nettype none
`timescale 1ns / 1ps

module serdesphy_pll_ctrl (
    input  wire       clk_ref_24m,
    input  wire       rst_n,

    input  wire       phy_en,
    input  wire [3:0] csr_vco_trim,
    input  wire       cal_enable,

    input  wire [7:0] loop_filter_out,

    input  wire       pll_lock_raw,
    input  wire       pll_vco_ok,
    input  wire       pll_cp_ok,

    output wire       pll_lock,
    output wire       pll_ready,
    output wire [7:0] pll_status,
    output wire       pll_error,

    output wire [3:0] vco_trim_out,
    output wire       cal_done,
    output wire       cal_active
);

    localparam LOCK_COUNT_MAX = 16'd4;
    localparam UNLOCK_COUNT   = 16'd240;

    localparam [1:0]
        LOCK_STATE_UNLOCKED  = 2'b00,
        LOCK_STATE_ACQUIRING = 2'b01,
        LOCK_STATE_LOCKED    = 2'b10;

    reg [1:0]  lock_state;
    reg [15:0] lock_counter;
    reg [15:0] unlock_counter;
    reg        pll_lock_reg;
    reg        pll_ready_reg;

    // The analog PLL's lock signal is already a frequency-window decision; do
    // not stack a second, narrower loop-filter window on top of it (that was
    // circular with calibration).
    wire pll_healthy = phy_en && pll_lock_raw && pll_vco_ok && pll_cp_ok &&
                       (!cal_enable || cal_done_reg);

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

                default: lock_state <= LOCK_STATE_UNLOCKED;
            endcase
        end
    end

    assign pll_lock   = pll_lock_reg;
    assign pll_ready  = pll_ready_reg;
    assign pll_error  = 1'b0;
    assign pll_status = {4'b0000, pll_cp_ok, pll_vco_ok, pll_lock_raw, phy_en};

    // =========================================================================
    // Closed-loop VCO trim calibration
    // =========================================================================

    localparam [2:0]
        CAL_IDLE   = 3'b000,
        CAL_SETTLE = 3'b001,
        CAL_CHECK  = 3'b010,
        CAL_UPDATE = 3'b011,
        CAL_DONE   = 3'b100;

    localparam integer CAL_SETTLE_CYCLES = 192; // ~8 us at 24 MHz
    localparam integer CAL_CHECK_CYCLES  = 64;  // extra lock-check window
    localparam integer MAX_ITERATIONS    = 4;

    localparam [7:0] CTRL_CENTER = 8'd128;
    localparam [7:0] CTRL_WINDOW = 8'd16;       // +/-2% of VCO range

    reg [2:0]  cal_state;
    reg [3:0]  vco_trim_cal;
    reg [4:0]  search_min;                      // 5-bit: can hold 16 (one past 15)
    reg [4:0]  search_max;
    reg [4:0]  new_min;
    reg [4:0]  new_max;
    reg [4:0]  mid_trim;
    reg [15:0] cal_timer;
    reg [2:0]  cal_iteration;
    reg        cal_done_reg;
    reg        pll_cp_ok_prev;

    always @(posedge clk_ref_24m or negedge rst_n) begin
        if (!rst_n) begin
            cal_state     <= CAL_IDLE;
            vco_trim_cal  <= 4'h8;
            search_min    <= 5'd0;
            search_max    <= 5'd15;
            new_min       <= 5'd0;
            new_max       <= 5'd15;
            mid_trim      <= 5'd8;
            cal_timer     <= 16'd0;
            cal_iteration <= 3'd0;
            cal_done_reg  <= 1'b0;
            pll_cp_ok_prev <= 1'b0;
        end else begin
            pll_cp_ok_prev <= pll_cp_ok;

            // Clear calibration whenever the PLL is disabled or reset. A raw
            // lock drop during a trim step is expected and must NOT abort it.
            if ((pll_cp_ok_prev && !pll_cp_ok) || !phy_en || !cal_enable) begin
                cal_done_reg <= 1'b0;
                cal_state    <= CAL_IDLE;
            end else begin
                case (cal_state)
                    CAL_IDLE: begin
                        if (cal_enable && phy_en && !cal_done_reg && pll_cp_ok) begin
                            vco_trim_cal  <= csr_vco_trim;
                            search_min    <= 5'd0;
                            search_max    <= 5'd15;
                            cal_timer     <= 16'd0;
                            cal_iteration <= 3'd0;
                            cal_state     <= CAL_SETTLE;
`ifndef SYNTHESIS
                            $display("[CAL] START calibration from CSR trim=%0d", csr_vco_trim);
`endif
                        end
                    end

                    CAL_SETTLE: begin
                        if (cal_timer < CAL_SETTLE_CYCLES) begin
                            cal_timer <= cal_timer + 1;
                        end else begin
                            cal_timer <= 16'd0;
                            cal_state <= CAL_CHECK;
                        end
                    end

                    CAL_CHECK: begin
                        if ((loop_filter_out >= CTRL_CENTER - CTRL_WINDOW) &&
                            (loop_filter_out <= CTRL_CENTER + CTRL_WINDOW) &&
                            pll_lock_raw) begin
                            cal_done_reg <= 1'b1;
                            cal_state    <= CAL_DONE;
`ifndef SYNTHESIS
                            $display("[CAL] DONE trim=%0d ctrl=%0d (in window, locked)",
                                     vco_trim_cal, loop_filter_out);
`endif
                        end else if (cal_timer < CAL_CHECK_CYCLES) begin
                            cal_timer <= cal_timer + 1;
                        end else begin
                            cal_timer <= 16'd0;
                            cal_state <= CAL_UPDATE;
                        end
                    end

                    CAL_UPDATE: begin
                        cal_iteration <= cal_iteration + 1'b1;
                        new_min = search_min;
                        new_max = search_max;

                        // Direction from the loop-filter control. Saturate the
                        // +/-1 steps instead of letting 4-bit arithmetic wrap.
                        if (loop_filter_out > CTRL_CENTER + CTRL_WINDOW) begin
                            // VCO too slow: raise the coarse trim.
                            if (vco_trim_cal < 4'hF)
                                new_min = {1'b0, vco_trim_cal} + 5'd1;
                            else begin
                                new_min = 5'd16;
                                new_max = 5'd15;
                            end
`ifndef SYNTHESIS
                            $display("[CAL] UPDATE ctrl=%0d high -> higher trim", loop_filter_out);
`endif
                        end else if (loop_filter_out < CTRL_CENTER - CTRL_WINDOW) begin
                            // VCO too fast: lower the coarse trim.
                            if (vco_trim_cal > 4'h0)
                                new_max = {1'b0, vco_trim_cal} - 5'd1;
                            else begin
                                new_min = 5'd1;
                                new_max = 5'd0;
                            end
`ifndef SYNTHESIS
                            $display("[CAL] UPDATE ctrl=%0d low -> lower trim", loop_filter_out);
`endif
                        end

                        if ((new_min > new_max) ||
                            (cal_iteration >= MAX_ITERATIONS - 1)) begin
                            cal_done_reg <= 1'b1;
                            cal_state    <= CAL_DONE;
`ifndef SYNTHESIS
                            $display("[CAL] DONE trim=%0d (search exhausted, ctrl=%0d)",
                                     vco_trim_cal, loop_filter_out);
`endif
                        end else begin
                            mid_trim = (new_min + new_max + 5'd1) >> 1;
                            search_min <= new_min;
                            search_max <= new_max;
                            vco_trim_cal <= mid_trim[3:0];
                            cal_state  <= CAL_SETTLE;
`ifndef SYNTHESIS
                            $display("[CAL] UPDATE iter=%0d range=[%0d:%0d] next trim=%0d",
                                     cal_iteration + 1, new_min, new_max, mid_trim);
`endif
                        end
                    end

                    CAL_DONE: begin
                        if (!cal_enable || !phy_en || !cal_done_reg)
                            cal_state <= CAL_IDLE;
                    end

                    default: cal_state <= CAL_IDLE;
                endcase
            end
        end
    end

    assign vco_trim_out = cal_enable ? vco_trim_cal : csr_vco_trim;
    assign cal_done     = cal_done_reg;
    assign cal_active   = (cal_state != CAL_IDLE) && (cal_state != CAL_DONE);

endmodule

`default_nettype wire
