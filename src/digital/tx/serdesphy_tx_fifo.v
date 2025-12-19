/*
 * SerDes PHY Transmit FIFO
 * 8-deep × 8-bit buffer clocked at 24 MHz
 * Supports 4-bit external interface with word assembly
 */

`default_nettype none

module serdesphy_tx_fifo (
    // Clock and reset
    input  wire        clk,
    input  wire        rst_n,
    
    // Control signals
    input  wire        enable,         // FIFO enable
    input  wire        write_enable,   // Write enable
    input  wire        read_enable,    // Read enable
    
    // Write interface (24 MHz domain)
    input  wire [7:0]  data_in,        // 8-bit parallel data in
    input  wire        write_valid,    // Write data valid
    
    // Read interface (24 MHz domain)  
    output wire [7:0]  data_out,       // 8-bit parallel data out
    output wire        read_valid,     // Read data valid
    
    // Status flags
    output wire        full,           // FIFO full flag
    output wire        empty,          // FIFO empty flag
    output wire        overflow,       // Overflow detected (sticky)
    output wire        underflow       // Underflow detected (sticky)
);

    // Parameters
    parameter FIFO_DEPTH = 8;
    parameter ADDR_WIDTH = 3;  // log2(FIFO_DEPTH)
    
    // Internal signals
    reg [ADDR_WIDTH-1:0] write_ptr;
    reg [ADDR_WIDTH-1:0] read_ptr;
    reg [7:0]            fifo_mem [0:FIFO_DEPTH-1];
    reg                  full_flag;
    reg                  empty_flag;
    reg                  overflow_flag;
    reg                  underflow_flag;
    
    // Write pointer management
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= 0;
        end else if (enable && write_enable && write_valid && !full_flag) begin
            fifo_mem[write_ptr] <= data_in;
            write_ptr <= write_ptr + 1;
        end
    end
    
    // Read pointer management
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_ptr <= 0;
        end else if (enable && read_enable && !empty_flag) begin
            read_ptr <= read_ptr + 1;
        end
    end
    
    // Full/empty flag calculation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            full_flag <= 0;
            empty_flag <= 1;
            overflow_flag <= 0;
            underflow_flag <= 0;
        end else if (enable) begin
            // Full condition: next write would make pointers equal but with different MSB
            full_flag <= (write_ptr == (read_ptr - 1));
            
            // Empty condition: pointers are equal
            empty_flag <= (write_ptr == read_ptr);
            
            // Overflow detection (write when full)
            if (write_enable && write_valid && full_flag) begin
                overflow_flag <= 1;
            end
            
            // Underflow detection (read when empty)
            if (read_enable && empty_flag) begin
                underflow_flag <= 1;
            end
        end
    end
    
    // Output assignments
    assign data_out = fifo_mem[read_ptr];
    assign read_valid = enable && read_enable && !empty_flag;
    assign full = full_flag;
    assign empty = empty_flag;
    assign overflow = overflow_flag;
    assign underflow = underflow_flag;

endmodule