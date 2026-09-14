/*
 * SerDes PHY PRBS Checker
 * PRBS-7 sequence checker with error detection
 * Compares decoded data against expected PRBS-7 sequence
 * Single-bit error detection per 8-bit word
 * Error counter saturates at 255
 */

`default_nettype none

module serdesphy_prbs_checker (
    // Clock and reset
    input  wire        clk,            // 24 MHz clock
    input  wire        rst_n,          // Active-low reset
    
    // Control signals
    input  wire        enable,         // Enable PRBS checker
    input  wire        reset_counter,   // Reset error counter
    input  wire        reset_alignment, // Reset alignment FSM

    // Clears prbs_error (STATUS.PRBS_ERR is sticky and clears on an I2C
    // read of STATUS - docs/info.md 5.7) without touching error_count,
    // which only RX_ALIGN_RST (reset_counter above) is defined to reset.
    input  wire        clear_sticky,

    // Input interface
    input  wire [7:0]  received_data, // 8-bit received data
    input  wire        data_valid,    // Received data valid
    
    // Output interface
    output wire        prbs_error,    // PRBS error detected (sticky)
    output wire [7:0] error_count,   // Error counter
    output wire        checker_busy   // Checker busy flag
);

    // Internal registers
    reg [6:0] prbs_shift_reg;    // Expected PRBS LFSR
    reg [7:0] expected_data_reg;
    reg [7:0] error_counter_reg;
    reg        error_detected_reg;
    reg        sticky_error_reg;
    reg [1:0] checker_state;
    reg        busy_flag;
    // Self-sync flag: is prbs_shift_reg known to actually track the live
    // transmitted sequence yet? See the STATE_IDLE comment below - a
    // fixed-state checker (always starting from 7'h7F) can only ever
    // match a transmitter that itself reset to 7'h7F at the exact same
    // instant, which never happens once any real alignment/lock
    // acquisition delay exists between them.
    reg        seeded;
    
    // State encoding
    localparam STATE_IDLE        = 2'b00;
    localparam STATE_CHECKING    = 2'b01;
    localparam STATE_ERROR       = 2'b10;
    localparam STATE_READY       = 2'b11;
    
    // PRBS-7 byte-wide advance: applies the x^7+x^6+1 Fibonacci LFSR
    // recurrence (fb = s[6]^s[5]; s <= {s[5:0], fb}) 8 times per call, MSB
    // of the output byte first. Must stay bit-for-bit identical to
    // serdesphy_prbs_generator.v's prbs7_advance_byte so the checker's
    // LFSR tracks the transmitter's. The previous version only computed a
    // correct feedback bit for bit 7 and then just copied the other 7
    // register bits through unshifted for bits 6..0 - starting from the
    // reset state 7'h7F (all ones), reordering all-1 bits yields all-1
    // bits again, so that formula was a genuine fixed point: the checker's
    // LFSR (and the TX generator's, which had the same bug) could never
    // leave 7F, so "expected" was always 0x7F and PRBS mode carried a
    // constant, perfectly periodic byte instead of a pseudorandom one.
    function automatic [14:0] prbs7_advance_byte;
        input [6:0] state;
        integer i;
        reg [6:0] s;
        reg [7:0] b;
        reg        fb;
        begin
            s = state;
            for (i = 0; i < 8; i = i + 1) begin
                fb = s[6] ^ s[5];
                b[7-i] = fb;
                s = {s[5:0], fb};
            end
            prbs7_advance_byte = {s, b};
        end
    endfunction

    wire [14:0] prbs7_result     = prbs7_advance_byte(prbs_shift_reg);
    wire [7:0]  prbs_next_byte   = prbs7_result[7:0];
    wire [6:0]  prbs_next_state  = prbs7_result[14:8];

    // PRBS checker state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            checker_state <= STATE_IDLE;
            prbs_shift_reg <= 7'h7F;  // Non-zero initial state
            expected_data_reg <= 8'h00;
            error_counter_reg <= 8'h00;
            error_detected_reg <= 0;
            sticky_error_reg <= 0;
            busy_flag <= 1'b0;
            seeded <= 1'b0;
        end else if (reset_alignment || reset_counter) begin
            // docs/info.md 5.3: "RX_ALIGN_RST resets alignment FSM and
            // error counter" - serdesphy_rx_top.v wires reset_alignment
            // and reset_counter to the same rx_align_rst signal, so both
            // effects need to apply together when it's asserted. These
            // were previously chained as mutually-exclusive `else if`
            // branches: since reset_alignment was checked first, the
            // reset_counter branch (which clears error_counter_reg AND
            // sticky_error_reg) could never actually run - RX_ALIGN_RST
            // silently failed to clear the sticky PRBS_ERR flag at all,
            // no matter how long it was held, even though the alignment
            // FSM itself did correctly reset.
            if (reset_alignment) begin
                checker_state <= STATE_IDLE;
                prbs_shift_reg <= 7'h7F;  // Reset alignment
                expected_data_reg <= 8'h00;
                error_detected_reg <= 0;
                busy_flag <= 1'b0;
                seeded <= 1'b0;
            end
            if (reset_counter) begin
                error_counter_reg <= 8'h00;
                sticky_error_reg <= 0;
            end
        end else if (clear_sticky) begin
            sticky_error_reg <= 0;
        end else if (!enable) begin
            checker_state <= STATE_IDLE;
            busy_flag <= 1'b0;
        end else begin
            case (checker_state)
                STATE_IDLE: begin
                    error_detected_reg <= 0;
                    busy_flag <= 1'b0;
                    if (data_valid) begin
                        if (!seeded) begin
                            // Self-sync on the first live word instead of
                            // assuming the transmitter's LFSR happened to
                            // reset to 7'h7F at exactly the same instant
                            // this checker did - it never does, since
                            // enable/reset_alignment fire on whatever
                            // schedule the CSR writes and alignment
                            // acquisition land on, long after the TX
                            // generator (which resets independently, at
                            // power-up) has already advanced far past its
                            // own initial state. Any 8 consecutive real
                            // PRBS-7 output bits deterministically pin
                            // down the generator's LFSR state (this
                            // function's own recurrence: the state right
                            // after producing a byte is exactly that
                            // byte's low 7 bits - see prbs7_advance_byte),
                            // so seeding prbs_shift_reg directly from the
                            // first observed byte, with nothing to compare
                            // it against, locks the checker onto the live
                            // sequence from the very next word on.
                            prbs_shift_reg <= received_data[6:0];
                            seeded         <= 1'b1;
                        end else begin
                            expected_data_reg <= prbs_next_byte;
                            prbs_shift_reg    <= prbs_next_state;
                            checker_state     <= STATE_CHECKING;
                        end
                    end
                end
                
                STATE_CHECKING: begin
                    busy_flag <= 1'b1;
                    // Check for errors
                    if (received_data != expected_data_reg) begin
                        error_detected_reg <= 1;
                        sticky_error_reg <= 1;
                        // Increment error counter (saturate at 255)
                        if (error_counter_reg < 8'hFF) begin
                            error_counter_reg <= error_counter_reg + 1;
                        end
                        checker_state <= STATE_ERROR;
                    end else begin
                        error_detected_reg <= 0;
                        checker_state <= STATE_READY;
                    end
                end
                
                STATE_ERROR: begin
                    error_detected_reg <= 1;
                    checker_state <= STATE_READY;
                end
                
                STATE_READY: begin
                    error_detected_reg <= 0;
                    busy_flag <= 1'b0;
                    checker_state <= STATE_IDLE;
                end
                
                default: begin
                    checker_state <= STATE_IDLE;
                end
            endcase
        end
    end
    
    // Output assignments
    assign prbs_error = sticky_error_reg;
    assign error_count = error_counter_reg;
    assign checker_busy = busy_flag;

endmodule