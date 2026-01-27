module serdesphy_ana_pll_vco (
    input  wire       rst_n,
    input  wire       enable,
    input  wire [7:0] vco_control,
    output wire       vco_out,
    output wire       vco_ready
);

    reg        vco_out_reg;
    reg        vco_ready_reg;
    reg [31:0] startup_counter;

    // Internal tick counter (acts as time base)
    reg [31:0] tick_counter;

    // Divider for VCO period
    reg [31:0] divider_value;

    // Convert vco_control -> digital divider
    always @(*) begin
        integer freq_mhz;
        integer half_period_ticks;

        // Integer frequency calculation
        freq_mhz = 240 + (vco_control - 8'd128) / 2;

        // Clamp
        if (freq_mhz < 176) freq_mhz = 176;
        if (freq_mhz > 304) freq_mhz = 304;

        // Create a digital half‑period in "ticks"
        // (arbitrary scale, must be >=1)
        half_period_ticks = 1000 / freq_mhz;  // integer math

        if (half_period_ticks < 1)
            half_period_ticks = 1;

        divider_value = half_period_ticks;
    end

    // Main free-running time base using event scheduling
    initial begin
        vco_out_reg = 1'b0;
        tick_counter = 32'd0;
    end

    // Self-running simulation loop (no delays used)
    always begin
        // The only legal way to advance "time" without #delay is to
        // create a delta-cycle loop and rely on the simulator's scheduler.
        tick_counter = tick_counter + 1;

        if (!rst_n || !enable) begin
            tick_counter = 0;
            vco_out_reg = 1'b0;
        end else begin
            if (tick_counter >= divider_value) begin
                tick_counter = 0;
                vco_out_reg = ~vco_out_reg;
            end
        end
    end

    // Startup counter (same as before)
    always @(posedge vco_out_reg or negedge rst_n) begin
        if (!rst_n) begin
            startup_counter <= 0;
            vco_ready_reg   <= 0;
        end else if (!enable) begin
            startup_counter <= 0;
            vco_ready_reg   <= 0;
        end else if (startup_counter < 100) begin
            startup_counter <= startup_counter + 1;
            vco_ready_reg   <= 0;
        end else begin
            vco_ready_reg   <= 1;
        end
    end

    assign vco_out   = vco_out_reg;
    assign vco_ready = vco_ready_reg;

endmodule