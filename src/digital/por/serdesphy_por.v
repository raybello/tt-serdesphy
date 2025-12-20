/*
 * SerDes PHY Power-On-Reset Controller
 * Handles proper power-up sequencing and reset generation
 * Manages supply monitoring and analog isolation control
 */

`default_nettype none

module serdesphy_por (
    // Supply monitoring inputs
    input  wire       dvdd_ok,         // 1.8V digital supply OK
    input  wire       avdd_ok,         // 3.3V analog supply OK
    
    // External reset and clock
    input  wire       rst_n_in,         // External active-low reset
    input  wire       clk,              // Reference clock
    
    // Control inputs
    input  wire       phy_en,           // PHY enable from CSR
    input  wire       iso_en,           // Analog isolation enable
    
    // Power sequencing outputs
    output wire       power_good,       // Power supplies stable and ready
    output wire       analog_iso_n,     // Analog isolation control (active-low)
    output wire       digital_reset_n,  // Digital domain reset release
    output wire       analog_reset_n,   // Analog domain reset release
    
    // Status outputs
    output wire       por_active,       // POR sequence active
    output wire       por_complete      // POR sequence complete
);

    // Internal state machine
    localparam [3:0] 
        STATE_POR_RESET     = 4'b0000,  // Initial reset state
        STATE_WAIT_SUPPLY   = 4'b0001,  // Wait for supplies to stabilize
        STATE_ANALOG_ISO    = 4'b0010,  // Apply analog isolation
        STATE_DIGITAL_PULSE = 4'b0011,  // Pulse digital reset
        STATE_ANALOG_PULSE  = 4'b0100,  // Pulse analog reset
        STATE_RELEASE_ISO   = 4'b0101,  // Release analog isolation
        STATE_READY         = 4'b0110,  // System ready
        STATE_ERROR         = 4'b0111;  // Error state
    
    // Timing constants (in 24MHz clock cycles)
    localparam [15:0] SUPPLY_STABLE_TIME = 16'd20;    // ~42us
    localparam [15:0] RESET_PULSE_TIME   = 16'd10;      // ~417ns
    localparam [15:0] ISO_SETTLE_TIME    = 16'd15;     // ~4us
    
    // State registers
    reg [3:0]   por_state;
    reg [15:0]  timer;
    reg         power_good_reg;
    reg         analog_iso_n_reg;
    reg         digital_reset_n_reg;
    reg         analog_reset_n_reg;
    reg         por_active_reg;
    reg         por_complete_reg;
    
    // Supply validation
    wire supplies_ok = dvdd_ok && avdd_ok;
    
    // State machine main logic
    always @(posedge clk or negedge rst_n_in) begin
        if (!rst_n_in) begin
            por_state <= STATE_POR_RESET;
            timer <= 16'd0;
            power_good_reg <= 1'b0;
            analog_iso_n_reg <= 1'b1;      // Start with isolation disabled
            digital_reset_n_reg <= 1'b0;    // Start with digital in reset
            analog_reset_n_reg <= 1'b0;     // Start with analog in reset
            por_active_reg <= 1'b1;         // POR active
            por_complete_reg <= 1'b0;       // POR not complete
        end else begin
            case (por_state)
                STATE_POR_RESET: begin
                    por_active_reg <= 1'b1;
                    por_complete_reg <= 1'b0;
                    power_good_reg <= 1'b0;
                    analog_iso_n_reg <= 1'b1;
                    digital_reset_n_reg <= 1'b0;
                    analog_reset_n_reg <= 1'b0;
                    timer <= 16'd0;
                    
                    if (supplies_ok) begin
                        por_state <= STATE_WAIT_SUPPLY;
                        timer <= SUPPLY_STABLE_TIME;
                    end
                end
                
                STATE_WAIT_SUPPLY: begin
                    if (!supplies_ok) begin
                        por_state <= STATE_POR_RESET;
                    end else if (timer == 16'd0) begin
                        por_state <= STATE_ANALOG_ISO;
                        timer <= ISO_SETTLE_TIME;
                    end else begin
                        timer <= timer - 1;
                    end
                end
                
                STATE_ANALOG_ISO: begin
                    analog_iso_n_reg <= iso_en ? 1'b0 : 1'b1;  // Apply isolation if requested
                    
                    if (timer == 16'd0) begin
                        por_state <= STATE_DIGITAL_PULSE;
                        timer <= RESET_PULSE_TIME;
                    end else begin
                        timer <= timer - 1;
                    end
                end
                
                STATE_DIGITAL_PULSE: begin
                    digital_reset_n_reg <= 1'b0;  // Keep digital in reset
                    
                    if (timer == 16'd0) begin
                        digital_reset_n_reg <= 1'b1;  // Release digital reset
                        por_state <= STATE_ANALOG_PULSE;
                        timer <= RESET_PULSE_TIME;
                    end else begin
                        timer <= timer - 1;
                    end
                end
                
                STATE_ANALOG_PULSE: begin
                    analog_reset_n_reg <= 1'b0;  // Keep analog in reset
                    
                    if (timer == 16'd0) begin
                        analog_reset_n_reg <= 1'b1;  // Release analog reset
                        por_state <= STATE_RELEASE_ISO;
                        timer <= ISO_SETTLE_TIME;
                    end else begin
                        timer <= timer - 1;
                    end
                end
                
                STATE_RELEASE_ISO: begin
                    if (timer == 16'd0) begin
                        analog_iso_n_reg <= 1'b1;  // Release analog isolation
                        por_state <= STATE_READY;
                    end else begin
                        timer <= timer - 1;
                    end
                end
                
                STATE_READY: begin
                    power_good_reg <= supplies_ok && phy_en;
                    por_active_reg <= 1'b0;
                    por_complete_reg <= 1'b1;
                    
                    // Check for supply loss or PHY disable
                    if (!supplies_ok || !phy_en) begin
                        por_state <= STATE_POR_RESET;
                    end
                end
                
                STATE_ERROR: begin
                    // Error state - require external reset to recover
                    por_active_reg <= 1'b0;
                    por_complete_reg <= 1'b0;
                    power_good_reg <= 1'b0;
                    
                    if (!rst_n_in) begin
                        por_state <= STATE_POR_RESET;
                    end
                end
                
                default: begin
                    por_state <= STATE_ERROR;
                end
            endcase
        end
    end
    
    // Output assignments
    assign power_good = power_good_reg;
    assign analog_iso_n = analog_iso_n_reg;
    assign digital_reset_n = digital_reset_n_reg;
    assign analog_reset_n = analog_reset_n_reg;
    assign por_active = por_active_reg;
    assign por_complete = por_complete_reg;

endmodule