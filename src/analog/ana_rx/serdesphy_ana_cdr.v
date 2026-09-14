/*
 * SerDes PHY CDR (Clock Data Recovery)
 * Bang-bang phase detector with Alexander architecture
 *
 * Lock declaration is based on whether the phase detector's early/late
 * decisions are BALANCED over a sliding window, rather than absent:
 * Manchester encoding guarantees a transition at every bit's own
 * midpoint, so roughly half of all consecutive-sample comparisons are
 * forced into an early/late (never "no correction needed") classification
 * purely by the encoding, independent of how well the recovered clock is
 * actually phase-aligned - "no transition seen for N cycles in a row" can
 * essentially never happen here even at perfect lock, so it cannot be the
 * lock criterion. What DOES distinguish locked from unlocked is whether
 * those decisions are trending consistently in one direction (still
 * converging) or dithering roughly evenly between early/late (settled):
 * a signed accumulator increments on early, decrements on late, and is
 * checked against a threshold every BALANCE_WINDOW cycles - small
 * magnitude means the last window's corrections roughly canceled out,
 * i.e. the loop has settled near its lock point. See
 * docs/implementation/01-spec-vs-implementation.md Finding 2.2 and
 * docs/implementation/cdr_vco/README.md section 5: this used to be a
 * fixed cycle counter, unrelated to whether serdesphy_ana_cdr_vco.v had
 * actually converged onto the incoming data's phase (the VCO's output
 * was architecturally bypassed entirely, so lock timing was disconnected
 * from reality either way).
 */

`default_nettype none

module serdesphy_ana_cdr (
    // Clock and reset
    input  wire       clk_240m_rx,     // 240 MHz recovered clock
    input  wire       rst_n,           // Active-low reset
    input  wire       cdr_rst,         // CDR reset
    input  wire       enable,          // CDR enable
    
    // Control inputs
    input  wire [2:0] cdr_gain,        // CDR gain setting
    input  wire       cdr_fast_lock,    // Fast acquisition mode
    
    // Data inputs
    input  wire       serial_data,      // Serial data input
    
    // VCO interface
    output wire [7:0] vco_control,     // VCO control voltage
    output wire       cdr_lock,        // CDR lock indicator
    output wire [7:0] phase_detector   // Phase detector output
);

    // Internal CDR model (simplified)
    reg        cdr_lock_reg;
    reg [7:0]  vco_control_reg;
    reg [7:0]  phase_detector_reg;
    reg [1:0]  cdr_state;
    reg [10:0] lock_counter;
    reg        early_sample, late_sample;
    reg        serial_data_prev;  // One-cycle delayed sample for Alexander phase detection
    
    // State encoding
    localparam STATE_RESET    = 2'b00;
    localparam STATE_ACQUIRE  = 2'b01;
    localparam STATE_TRACK    = 2'b10;
    localparam STATE_LOCKED   = 2'b11;

    // Balance-window lock detector (see file header comment above).
    // MIN_ACTIVITY additionally requires a minimum number of actual
    // transitions during the window: with no incoming data (or a
    // constant line level), every sample pair reads as "no transition"
    // (phase_detector_reg == 8'h80), which a pure balance check can't
    // distinguish from genuinely centered/locked - both give
    // balance_accum == 0. Real Manchester-coded data guarantees a
    // transition at every bit's own midpoint, so a locked, active link
    // should see transitions on a healthy fraction of cycles; silence
    // should not.
    localparam [8:0]        BALANCE_WINDOW    = 9'd256;
    localparam signed [8:0] BALANCE_THRESHOLD = 9'sd32;
    localparam [8:0]        MIN_ACTIVITY      = 9'd24;

    reg signed [8:0] balance_accum;
    reg [8:0]        activity_count;
    reg [8:0]        window_count;

    // Signed phase-error deviation from mid-scale (8'h80), used by the
    // gain-scaled tracking corrections below. phase_detector_reg is an
    // unsigned reg, so `phase_detector_reg - 8'h80` on its own computes as
    // an 8-bit UNSIGNED wraparound subtraction: for the "slow down" case
    // (phase_detector_reg < 8'h80), that underflows to a large unsigned
    // value (e.g. 124 -> 252 instead of -4). A later `>>` (logical shift)
    // on that wrapped value does NOT correctly divide a negative number -
    // it silently produces a huge, essentially nonsensical result instead
    // (252 >> 2 = 63, not the correct -1). This is exactly the kind of
    // bug that only shows up intermittently (only when phase_detector_reg
    // is below mid-scale, i.e. only on "late" decisions) and, run through
    // serdesphy_ana_cdr_vco.v's phase-tracking model, injects an
    // occasional large, essentially random timing kick into the
    // recovered clock - a very plausible root cause of the sparse
    // PRBS_ERR events documented in docs/implementation/00-fixes-applied.md
    // section 4. Fixed by computing the deviation as a genuinely signed
    // value up front and using the arithmetic shift operator (`>>>`),
    // which sign-extends correctly, wherever it's scaled below.
    wire signed [8:0] pd_deviation = $signed({1'b0, phase_detector_reg}) -
                                     $signed({1'b0, 8'h80});

    // Alexander phase detector model
    always @(posedge clk_240m_rx or negedge rst_n) begin
        if (!rst_n) begin
            early_sample    <= 0;
            late_sample     <= 0;
            serial_data_prev <= 0;
        end else if (cdr_rst) begin
            early_sample    <= 0;
            late_sample     <= 0;
            serial_data_prev <= 0;
        end else if (enable) begin
            // Alexander phase detector: compare current sample (late) with
            // previous-cycle sample (early) to sense data transitions.
            serial_data_prev <= serial_data;
            early_sample <= serial_data_prev;  // Sample from previous cycle
            late_sample  <= serial_data;        // Sample from current cycle
        end
    end

    // Phase detector output
    always @(posedge clk_240m_rx or negedge rst_n) begin
        if (!rst_n) begin
            phase_detector_reg <= 8'h80;  // Mid-scale
        end else if (cdr_rst) begin
            phase_detector_reg <= 8'h80;  // Mid-scale
        end else if (enable) begin
            // Bang-bang phase detector logic
            if (early_sample && !late_sample) begin
                phase_detector_reg <= 8'h80 + cdr_gain;  // Speed up
            end else if (!early_sample && late_sample) begin
                phase_detector_reg <= 8'h80 - cdr_gain;  // Slow down
            end else begin
                phase_detector_reg <= 8'h80;  // Just right
            end
        end
    end

    // CDR state machine
    always @(posedge clk_240m_rx or negedge rst_n) begin
        if (!rst_n) begin
            cdr_state <= STATE_RESET;
            cdr_lock_reg <= 0;
            vco_control_reg <= 8'h80;  // Mid-scale
            lock_counter <= 11'h000;
            balance_accum <= 9'sh000;
            activity_count <= 9'h000;
            window_count <= 9'h000;
        end else if (cdr_rst || !enable) begin
            cdr_state <= STATE_RESET;
            cdr_lock_reg <= 0;
            lock_counter <= 11'h000;
            balance_accum <= 9'sh000;
            activity_count <= 9'h000;
            window_count <= 9'h000;
        end else begin
            case (cdr_state)
                STATE_RESET: begin
                    vco_control_reg <= 8'h80;
                    cdr_state <= STATE_ACQUIRE;
                    lock_counter <= 11'h000;
                    balance_accum <= 9'sh000;
                    activity_count <= 9'h000;
                    window_count <= 9'h000;
                end

                STATE_ACQUIRE: begin
                    // Fast acquisition mode. (Left-shift-by-1 on the raw
                    // unsigned wraparound subtraction happens to double a
                    // two's-complement value correctly regardless of
                    // signedness - unlike the right-shift case fixed
                    // below - but using the signed deviation here too for
                    // clarity/consistency rather than relying on that.)
                    if (cdr_fast_lock) begin
                        vco_control_reg <= phase_detector_reg + (pd_deviation <<< 1);
                    end else begin
                        vco_control_reg <= phase_detector_reg;
                    end

                    // Balance-window lock detector (see file header
                    // comment): accumulate signed early(+1)/late(-1) per
                    // cycle; every BALANCE_WINDOW cycles, a small-magnitude
                    // accumulator means this window's corrections roughly
                    // canceled out, i.e. the VCO has settled near the
                    // incoming data's phase rather than still converging.
                    if (window_count >= BALANCE_WINDOW - 1'b1) begin
                        window_count   <= 9'h000;
                        balance_accum  <= 9'sh000;
                        activity_count <= 9'h000;
                        if ((balance_accum >= -BALANCE_THRESHOLD) &&
                            (balance_accum <= BALANCE_THRESHOLD) &&
                            (activity_count >= MIN_ACTIVITY)) begin
                            cdr_state    <= STATE_LOCKED;
                            cdr_lock_reg <= 1;
                        end
                    end else begin
                        window_count <= window_count + 1'b1;
                        if (phase_detector_reg == (8'h80 + cdr_gain)) begin
                            balance_accum  <= balance_accum + 1'sb1;
                            activity_count <= activity_count + 1'b1;
                        end else if (phase_detector_reg == (8'h80 - cdr_gain)) begin
                            balance_accum  <= balance_accum - 1'sb1;
                            activity_count <= activity_count + 1'b1;
                        end
                    end
                end

                STATE_TRACK: begin
                    // Normal tracking mode
                    vco_control_reg <= phase_detector_reg;
                end
                
                STATE_LOCKED: begin
                    cdr_lock_reg <= 1;
                    // Continue tracking but with reduced gain. See
                    // pd_deviation's declaration above for why this must
                    // use the signed deviation + arithmetic shift (`>>>`)
                    // rather than shifting the raw unsigned subtraction.
                    vco_control_reg <= phase_detector_reg + (pd_deviation >>> 2);
                end
                
                default: begin
                    cdr_state <= STATE_RESET;
                end
            endcase
        end
    end
    
    // Output assignments
    assign vco_control = vco_control_reg;
    assign cdr_lock = cdr_lock_reg;
    assign phase_detector = phase_detector_reg;

endmodule