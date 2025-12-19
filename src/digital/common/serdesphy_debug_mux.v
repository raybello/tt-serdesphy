/*
 * SerDes PHY Debug Multiplexer
 * Debug output multiplexer for analog signals
 * Routes selected debug signal to DBG_ANA output
 */

`default_nettype none

module serdesphy_debug_mux (
    // Clock and reset
    input  wire       clk,             // System clock
    input  wire       rst_n,           // Active-low reset
    
    // Control inputs from CSR
    input  wire       dbg_vctrl,        // Route VCO control voltage
    input  wire       dbg_pd,           // Route phase detector output
    input  wire       dbg_fifo,         // Route FIFO status
    
    // Debug input signals (from analog blocks)
    input  wire [7:0]  vco_control,    // VCO control voltage (digital representation)
    input  wire [7:0]  phase_detector,  // Phase detector output
    input  wire [7:0]  fifo_status,     // FIFO status bits
    
    // Debug output
    output wire [7:0]  debug_analog    // Analog debug buffer output
);

    // Internal multiplexer
    reg [7:0] debug_output_reg;
    
    // Debug signal selection logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            debug_output_reg <= 8'h00;
        end else begin
            case (1'b1)
                dbg_vctrl: debug_output_reg <= vco_control;
                dbg_pd:    debug_output_reg <= phase_detector;
                dbg_fifo:  debug_output_reg <= fifo_status;
                default:   debug_output_reg <= 8'h00;  // No debug selected
            endcase
        end
    end
    
    // Output assignment
    assign debug_analog = debug_output_reg;

endmodule