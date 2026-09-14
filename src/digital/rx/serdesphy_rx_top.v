/*
 * SerDes PHY Receive Top Module
 * Receive controller FSM with alignment and synchronization
 * Orchestrates manchester_decoder → rx_fifo → word_disassembler pipeline
 * Handles clock domain crossing, alignment, and error detection
 */

`default_nettype none

module serdesphy_rx_top (
    // Clock and reset
    input  wire       clk_24m,          // 24 MHz system clock
    input  wire       clk_240m_rx,      // 240 MHz RX clock (from CDR)
    input  wire       rst_n_24m,         // 24MHz domain reset
    input  wire       rst_n_240m_rx,     // 240MHz RX domain reset
    
    // Control inputs from CSR
    input  wire       rx_en,            // Receive enable
    input  wire       rx_fifo_en,       // RX FIFO enable
    input  wire       rx_prbs_chk_en,   // RX PRBS check enable
    input  wire       rx_align_rst,     // Reset alignment FSM
    input  wire       rx_data_sel,      // RX output select (0=FIFO, 1=PRBS status)
    
    // Serial input interface from analog deserializer
    input  wire       rx_serial_data,   // Serial data from deserializer
    input  wire       rx_serial_valid,  // Serial data valid
    input  wire       rx_serial_error,  // Serial data error
    
    // External RX data interface
    output wire [3:0] rx_data,          // 4-bit receive data
    output wire       rx_valid,         // RX data valid strobe
    
    // Status outputs to CSR
    output wire       rx_fifo_full,     // RX FIFO full flag
    output wire       rx_fifo_empty,    // RX FIFO empty flag
    output wire       rx_overflow,      // RX FIFO overflow (sticky)
    output wire       rx_underflow,     // RX FIFO underflow (sticky)
    output wire       rx_active,        // RX data path active
    output wire       rx_error,         // RX error flag
    output wire       rx_aligned,       // RX alignment achieved
    output wire       prbs_err,         // PRBS error indication

    // Clock domain status
    input  wire       clk_240m_rx_en,   // 240MHz RX clock enable

    // Clears rx_overflow/rx_underflow/prbs_err (STATUS.FIFO_ERR and
    // STATUS.PRBS_ERR are sticky and clear on an I2C read of STATUS -
    // docs/info.md 5.7)
    input  wire       status_read_clear
);

    // RX Controller State Machine
    localparam [2:0]
        RX_STATE_DISABLED  = 3'b000,  // RX disabled
        RX_STATE_ALIGNING  = 3'b001,  // Aligning to Manchester pattern
        RX_STATE_ACQUIRING = 3'b010,  // Acquiring bit/word synchronization
        RX_STATE_ACTIVE    = 3'b011,  // RX actively receiving
        RX_STATE_ERROR     = 3'b100;  // Error state
    
    // Alignment FSM states
    localparam [1:0]
        ALIGN_STATE_SEARCH   = 2'b00,  // Search for Manchester pattern
        ALIGN_STATE_VERIFY   = 2'b01,  // Verify pattern stability
        ALIGN_STATE_LOCKED   = 2'b10;  // Pattern locked
    
    // Internal signals
    reg [2:0]   rx_state;
    reg [1:0]   align_state;
    reg [15:0]  serial_shift_reg;
    reg [3:0]   serial_bit_count;
    reg [15:0]  manchester_word_reg;
    reg         manchester_word_valid;
    reg         rx_active_reg;
    reg         rx_error_reg;
    reg         rx_aligned_reg;
    reg [7:0]   manchester_data_out;
    reg         manchester_data_valid;
    reg         fifo_write_enable;
    reg         fifo_read_enable;
    reg [2:0]   error_count;
    reg [7:0]   align_count;
    reg [7:0]   verify_count;
    
    // Manchester decoder interface
    wire [7:0]  manchester_decoder_out;
    wire        manchester_decoder_valid;
    wire        manchester_decoder_error;
    
    // RX FIFO interface
    wire [7:0]  rx_fifo_data_out;
    wire        rx_fifo_empty_wire;
    wire        rx_fifo_full_wire;
    wire        rx_fifo_overflow_wire;
    wire        rx_fifo_underflow_wire;
    wire        rx_fifo_rd_valid;
    
    // Word disassembler interface
    wire [3:0]  word_disassembler_out;
    wire        word_disassembler_valid;
    
    // PRBS checker interface
    wire        prbs_error_wire;
    wire [7:0]  prbs_error_count;
    
    // Sticky error registers
    reg         overflow_sticky;
    reg         underflow_sticky;
    reg         manchester_error_sticky;
    reg         serial_error_sticky;
    
    // Counts consecutive clk_240m_rx cycles with no valid Manchester
    // window found, while aligned (ALIGN_STATE_LOCKED below) - i.e. time
    // since the last confirmed-good word, not a count of discrete
    // "invalid windows" (manchester_word_valid, by construction below,
    // only ever pulses for a window already confirmed valid - there is no
    // separate "saw an invalid window" event to count anymore). Sized and
    // thresholded to comfortably span a normal idle gap between words
    // (tens to ~100ns under minimum-effective-rate host pacing) while
    // still detecting genuine loss of signal within a few us - see
    // ALIGN_STATE_LOCKED.
    reg [11:0]  no_valid_word_count;

    // Additional interface wires
    wire        word_disassembler_ready;
    wire        prbs_checker_busy;

    // Valid Manchester check: every 2-bit symbol (bits [2i+1:2i]) must
    // differ, i.e. be 01 or 10 (never 00 or 11).
    function automatic bit valid_manchester_word(input [15:0] w);
        valid_manchester_word = (w[1]  ^ w[0])  && (w[3]  ^ w[2])  &&
                                (w[5]  ^ w[4])  && (w[7]  ^ w[6])  &&
                                (w[9]  ^ w[8])  && (w[11] ^ w[10]) &&
                                (w[13] ^ w[12]) && (w[15] ^ w[14]);
    endfunction

    // Instantiate Manchester decoder - clocked by clk_240m_rx (the
    // domain manchester_word_reg/manchester_word_valid actually live in),
    // not clk_24m. See the "Serial input accumulation" block below: once
    // clk_240m_rx became the genuinely independent CDR-recovered clock
    // (docs/implementation/01-spec-vs-implementation.md Finding 2.2),
    // manchester_word_valid's single-cycle pulse (asserted 1 out of every
    // 16 clk_240m_rx cycles) could be silently missed by a clk_24m-domain
    // reader - clk_24m's ~41.67ns period is longer than the ~66.7ns
    // between words but not by enough margin to guarantee catching a
    // single fast-domain cycle, and this specific rate ratio (240MHz/16
    // words vs 24MHz) is too tight for a hand-rolled toggle/pulse
    // synchronizer to guarantee lossless capture either. The actual CDC
    // boundary belongs at the FIFO below instead, which already exists
    // for exactly this purpose (gray-coded pointers tolerate arbitrary
    // relative clock rates without relying on catching a narrow pulse).
    serdesphy_manchester_decoder u_manchester_decoder (
        .clk             (clk_240m_rx),
        .rst_n           (rst_n_240m_rx),
        .manchester_data (manchester_word_reg),
        // Not additionally gated on rx_aligned_reg: manchester_word_valid
        // is already only ever pulsed for a window confirmed valid by
        // valid_manchester_word() (see the accumulation block above), so
        // there is no "unvalidated noise" for an alignment gate to guard
        // against here. Gating on rx_aligned_reg would also cost the
        // very word that causes alignment to be declared in the first
        // place: rx_aligned_reg (set by the alignment FSM, a separate
        // always block) only becomes readable as 1 one clk_240m_rx cycle
        // after the triggering manchester_word_valid pulse, by which time
        // that specific pulse has already ended.
        .data_valid      (manchester_word_valid && rx_en),
        .decoded_data    (manchester_decoder_out),
        .decode_valid    (manchester_decoder_valid),
        .decode_error    (manchester_decoder_error)
    );

    // Instantiate RX FIFO - this is the actual CDC boundary between the
    // clk_240m_rx (CDR-recovered) and clk_24m domains, using
    // serdesphy_rx_fifo's existing dual-clock gray-code pointer design
    // (already correct; it just used to be instantiated with both clocks
    // tied to clk_24m because there was nothing genuinely asynchronous
    // upstream of it before Finding 2.2's fix).
    serdesphy_rx_fifo u_rx_fifo (
        // Write clock domain (CDR-recovered 240MHz, ÷16 by the Manchester
        // decoder above to one 8-bit word every 16 clk_240m_rx cycles)
        .wr_clk          (clk_240m_rx),
        .wr_rst_n        (rst_n_240m_rx),
        .wr_enable       (rx_en && rx_fifo_en),
        .wr_data         (manchester_decoder_out),
        // manchester_decoder_valid alone pulses for every 16-bit window,
        // decoded or not: with no link activity (TX idle, or before
        // alignment), that window is a constant, non-toggling level with
        // no valid Manchester transitions, which the decoder correctly
        // flags via decode_error - forwarding it into the FIFO anyway
        // would flood all 8 entries with fake all-zero "bytes" every
        // 66.7ns, pushing out real data faster than it could ever be
        // read back out. Only cleanly-decoded windows should ever reach
        // the FIFO.
        .wr_valid        (manchester_decoder_valid && !manchester_decoder_error),

        // Read clock domain (24MHz system)
        .rd_clk          (clk_24m),
        .rd_rst_n        (rst_n_24m),
        .rd_enable       (rx_en && rx_fifo_en),
        .rd_data         (rx_fifo_data_out),
        .rd_valid        (rx_fifo_rd_valid),
        .rd_read_enable  (word_disassembler_ready),

        // Status flags
        .full            (rx_fifo_full_wire),
        .empty           (rx_fifo_empty_wire),
        .overflow        (rx_fifo_overflow_wire),
        .underflow       (rx_fifo_underflow_wire)
    );

    // Instantiate word disassembler
    serdesphy_word_disassembler u_word_disassembler (
        .clk            (clk_24m),
        .rst_n          (rst_n_24m),
        .rx_data_word   (rx_fifo_data_out),
        .rx_word_valid  (rx_fifo_rd_valid && rx_en && rx_fifo_en),
        .rx_data_nibble (word_disassembler_out),
        .rx_valid       (word_disassembler_valid),
        .rx_word_ready  (word_disassembler_ready)
    );

    // Instantiate PRBS checker - clocked by clk_240m_rx for the same
    // reason as the Manchester decoder above: it consumes
    // manchester_decoder_valid, the same fast-domain pulse.
    serdesphy_prbs_checker u_prbs_checker (
        .clk             (clk_240m_rx),
        .rst_n           (rst_n_240m_rx),
        .enable          (rx_en && rx_prbs_chk_en),
        .reset_counter   (rx_align_rst),
        .reset_alignment (rx_align_rst),
        .clear_sticky    (status_read_clear),
        .received_data   (manchester_decoder_out),
        .data_valid      (manchester_decoder_valid),
        .prbs_error      (prbs_error_wire),
        .error_count     (prbs_error_count),
        .checker_busy    (prbs_checker_busy)
    );
    
    // Serial input accumulation (240MHz domain)
    //
    // Checks the sliding 16-bit window with valid_manchester_word() every
    // single cycle, unconditionally - not just while unaligned, and not
    // on any fixed 16-cycle schedule either (a fixed-stride "skip ahead
    // 16 after a match" scheme was tried and measurably broke: RX's
    // serial samples come from cdr_clk_240m, the CDR's own independently
    // recovered behavioral VCO clock, which does not advance in lockstep
    // with clk_240m_tx bit-for-bit - a real 16-bit TX burst was observed
    // spanning quite a different number of clk_240m_rx cycles than 16,
    // so any scheme assuming exactly 16 RX cycles per word silently
    // desynced and skipped roughly every other real word).
    //
    // This works because genuine idle gaps between words are reliably
    // Manchester-INVALID here: rx_serial_valid does not actually track
    // TX activity (see serdesphy_deserializer_if.v - it reflects the
    // deserializer's own enable/lock state, not per-word framing), so
    // between real bursts the line simply carries TX's driven-low idle
    // level, i.e. genuine non-toggling zero bits - every 2-bit pair of
    // pure zeros is invalid Manchester, so a partially-flushed window
    // (old word's tail bits mixed with idle zeros, or idle zeros mixed
    // with a new word's leading bits) reliably fails the check until the
    // window is composed entirely of one real word's own 16 bits. There
    // is therefore no separate "trust the counter" steady-state mode
    // needed, nor the ambiguity a truly gapless continuous bitstream
    // would create (any even-bit-offset window of THAT would trivially
    // validate too) - this design's idle behavior avoids that case.
    //
    // manchester_word_valid is therefore always a genuine, pre-validated
    // one-cycle pulse: it only ever pulses for a window
    // valid_manchester_word() already confirmed, so nothing downstream
    // (the decoder in particular) needs to separately gate on alignment
    // status to avoid decoding noise.
    always @(posedge clk_240m_rx or negedge rst_n_240m_rx) begin
        if (!rst_n_240m_rx) begin
            serial_shift_reg <= 16'h0000;
            serial_bit_count <= 4'd0;
            manchester_word_reg <= 16'h0000;
            manchester_word_valid <= 1'b0;
        end else if (clk_240m_rx_en && rx_en) begin
            if (rx_serial_valid && !rx_serial_error) begin
                serial_shift_reg <= {serial_shift_reg[14:0], rx_serial_data};
                if (valid_manchester_word({serial_shift_reg[14:0], rx_serial_data})) begin
                    manchester_word_reg   <= {serial_shift_reg[14:0], rx_serial_data};
                    manchester_word_valid <= 1'b1;
                end else begin
                    manchester_word_valid <= 1'b0;
                end
            end else begin
                manchester_word_valid <= 1'b0;
            end
        end else begin
            manchester_word_valid <= 1'b0;
        end
    end
    
    // RX Controller State Machine
    always @(posedge clk_24m or negedge rst_n_24m) begin
        if (!rst_n_24m) begin
            rx_state <= RX_STATE_DISABLED;
            rx_active_reg <= 1'b0;
            rx_error_reg <= 1'b0;
            error_count <= 3'd0;
        end else begin
            case (rx_state)
                RX_STATE_DISABLED: begin
                    rx_active_reg <= 1'b0;
                    if (rx_en && clk_240m_rx_en) begin
                        rx_state <= RX_STATE_ALIGNING;
                    end
                end
                
                RX_STATE_ALIGNING: begin
                    if (!rx_en || !clk_240m_rx_en) begin
                        rx_state <= RX_STATE_DISABLED;
                    end else if (rx_align_rst) begin
                        // handled in alignment FSM
                    end else if (!rx_align_rst && rx_aligned_reg) begin
                        rx_state <= RX_STATE_ACQUIRING;
                    end else begin
                        // Alignment logic in separate always block
                    end
                end
                
                RX_STATE_ACQUIRING: begin
                    if (!rx_en || !clk_240m_rx_en) begin
                        rx_state <= RX_STATE_DISABLED;
                    end else if (manchester_data_valid) begin
                        rx_active_reg <= 1'b1;
                        rx_state <= RX_STATE_ACTIVE;
                    end
                end
                
                RX_STATE_ACTIVE: begin
                    if (!rx_en || !clk_240m_rx_en) begin
                        rx_state <= RX_STATE_DISABLED;
                        rx_active_reg <= 1'b0;
                    end else if (!rx_aligned_reg) begin
                        rx_state <= RX_STATE_ALIGNING;
                    end else if (manchester_decoder_error || rx_fifo_overflow_wire || 
                               rx_serial_error || prbs_error_wire) begin
                        if (error_count < 3'd7) begin
                            error_count <= error_count + 1;
                        end else begin
                            rx_state <= RX_STATE_ERROR;
                            rx_error_reg <= 1'b1;
                        end
                    end
                end
                
                RX_STATE_ERROR: begin
                    rx_active_reg <= 1'b0;
                    if (!rx_en) begin
                        rx_state <= RX_STATE_DISABLED;
                        rx_error_reg <= 1'b0;
                        error_count <= 3'd0;
                    end
                end
                
                default: begin
                    rx_state <= RX_STATE_ERROR;
                    rx_error_reg <= 1'b1;
                end
            endcase
        end
    end
    
    // Alignment state machine
    //
    // Simplified for behavioral simulation: lock on the FIRST valid Manchester
    // window, and stay locked through idle gaps (TX sends zeros between words).
    // Only unlock after 31 consecutive invalid windows (~3 µs of pure silence).
    //
    // Clocked by clk_240m_rx (not clk_24m) for the same reason as
    // u_manchester_decoder above: it reads manchester_word_valid directly,
    // a single-clk_240m_rx-cycle pulse.
    // docs/info.md 4.3's "~7-cycle gaps between words" undersells the
    // real idle gaps a min-rate host produces (see
    // docs/implementation/00-fixes-applied.md): under continuous
    // minimum-effective-rate (12MHz nibble) FIFO feeding, TX's own
    // 240MHz/16 word drain rate is faster than the nibble interface can
    // refill it, so genuine idle gaps of 100ns+ between words are normal,
    // not exceptional. NO_VALID_WORD_TIMEOUT is sized with generous
    // margin above that (a few us) so ordinary gaps never trip a false
    // unlock, while still detecting genuine loss of signal reasonably
    // quickly.
    localparam [11:0] NO_VALID_WORD_TIMEOUT = 12'd1000;  // ~4.17us @ 240MHz

    always @(posedge clk_240m_rx or negedge rst_n_240m_rx) begin
        if (!rst_n_240m_rx) begin
            align_state         <= ALIGN_STATE_SEARCH;
            align_count         <= 8'd0;
            verify_count        <= 8'd0;
            no_valid_word_count <= 12'd0;
            rx_aligned_reg      <= 1'b0;
        end else if (rx_align_rst || rx_state == RX_STATE_DISABLED || rx_state == RX_STATE_ERROR) begin
            align_state         <= ALIGN_STATE_SEARCH;
            align_count         <= 8'd0;
            verify_count        <= 8'd0;
            no_valid_word_count <= 12'd0;
            rx_aligned_reg      <= 1'b0;
        end else if (rx_state == RX_STATE_ALIGNING) begin
            case (align_state)
                ALIGN_STATE_SEARCH: begin
                    // manchester_word_valid only ever pulses for a window
                    // the accumulation block above already confirmed via
                    // valid_manchester_word() - no separate pattern check
                    // needed here.
                    if (manchester_word_valid) begin
                        // Lock immediately on first valid Manchester window
                        align_state         <= ALIGN_STATE_LOCKED;
                        rx_aligned_reg      <= 1'b1;
                        no_valid_word_count <= 12'd0;
                    end
                end

                ALIGN_STATE_LOCKED: begin
                    if (manchester_word_valid) begin
                        no_valid_word_count <= 12'd0;
                    end else if (no_valid_word_count < NO_VALID_WORD_TIMEOUT) begin
                        no_valid_word_count <= no_valid_word_count + 1'b1;
                    end else begin
                        align_state         <= ALIGN_STATE_SEARCH;
                        rx_aligned_reg      <= 1'b0;
                        no_valid_word_count <= 12'd0;
                    end
                end

                default: begin
                    align_state <= ALIGN_STATE_SEARCH;
                end
            endcase
        end
    end

    // Data flow control - clocked by clk_240m_rx: reads
    // manchester_decoder_valid (a single clk_240m_rx-cycle pulse) and
    // rx_fifo_full_wire (now driven by rx_fifo's wr_clk=clk_240m_rx side),
    // same reasoning as the blocks above. manchester_data_valid only
    // gates the RX_STATE_ACQUIRING->ACTIVE transition (rx_active status),
    // not the actual FIFO data path (rx_fifo's own wr_valid/rd_read_enable
    // drive that directly) - but it would still get stuck permanently low
    // if read from clk_24m instead, leaving rx_active wedged at 0.
    always @(posedge clk_240m_rx or negedge rst_n_240m_rx) begin
        if (!rst_n_240m_rx) begin
            manchester_data_valid <= 1'b0;
            fifo_write_enable <= 1'b0;
            fifo_read_enable <= 1'b0;
        end else begin
            // Feed Manchester decoder output to FIFO
            manchester_data_out <= manchester_decoder_out;
            manchester_data_valid <= manchester_decoder_valid && !rx_fifo_full_wire;
            
            // Read from FIFO when data available
            fifo_read_enable <= rx_en && rx_fifo_en && !rx_fifo_empty_wire;
        end
    end
    
    // Sticky error handling. status_read_clear takes priority over a
    // same-cycle set so a read always observes-then-clears rather than
    // racing a fresh overflow/underflow into "still stuck".
    always @(posedge clk_24m or negedge rst_n_24m) begin
        if (!rst_n_24m) begin
            overflow_sticky <= 1'b0;
            underflow_sticky <= 1'b0;
            manchester_error_sticky <= 1'b0;
            serial_error_sticky <= 1'b0;
        end else if (status_read_clear) begin
            overflow_sticky <= 1'b0;
            underflow_sticky <= 1'b0;
        end else begin
            if (rx_fifo_overflow_wire) overflow_sticky <= 1'b1;
            if (rx_fifo_underflow_wire) underflow_sticky <= 1'b1;
            if (manchester_decoder_error) manchester_error_sticky <= 1'b1;
            if (rx_serial_error) serial_error_sticky <= 1'b1;
        end
    end
    
    // Output multiplexing based on rx_data_sel
    // In PRBS status mode pulse rx_valid only when the decoder produces new data,
    // preventing a permanently-asserted valid from flooding the downstream interface.
    assign rx_data  = rx_data_sel ? prbs_error_count[3:0] : word_disassembler_out;
    assign rx_valid = rx_data_sel ? manchester_decoder_valid : word_disassembler_valid;
    
    // Status outputs
    assign rx_fifo_full = rx_fifo_full_wire;
    assign rx_fifo_empty = rx_fifo_empty_wire;
    assign rx_overflow = overflow_sticky;
    assign rx_underflow = underflow_sticky;
    assign rx_active = rx_active_reg;
    assign rx_error = rx_error_reg || manchester_error_sticky || serial_error_sticky;
    assign rx_aligned = rx_aligned_reg;
    assign prbs_err = prbs_error_wire;

endmodule