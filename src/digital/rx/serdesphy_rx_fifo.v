/*
 * SerDes PHY Receive FIFO
 * 8-deep × 8-bit buffer with clock domain crossing
 * Clocked at recovered 24 MHz domain
 */

`default_nettype none

module serdesphy_rx_fifo (
    // Write clock domain (recovered 24 MHz)
    input  wire        wr_clk,
    input  wire        wr_rst_n,
    input  wire        wr_enable,       // FIFO write enable
    input  wire [7:0]  wr_data,        // 8-bit parallel data in
    input  wire        wr_valid,       // Write data valid
    
    // Read clock domain (24 MHz system clock)  
    input  wire        rd_clk,
    input  wire        rd_rst_n,
    input  wire        rd_enable,       // FIFO read enable
    output wire [7:0]  rd_data,        // 8-bit parallel data out
    output wire        rd_valid,       // Read data valid
    input  wire        rd_read_enable, // Read data consumption
    
    // Status flags (synchronized to read clock domain)
    output wire        full,           // FIFO full flag
    output wire        empty,          // FIFO empty flag
    output wire        overflow,       // Overflow detected (sticky)
    output wire        underflow       // Underflow detected (sticky)
);

    // Parameters
    parameter FIFO_DEPTH = 8;
    parameter ADDR_WIDTH = 3;  // log2(FIFO_DEPTH)
    
    // Internal signals
    reg [ADDR_WIDTH:0] wr_ptr_gray, wr_ptr_gray_next;
    reg [ADDR_WIDTH:0] wr_ptr_binary, wr_ptr_binary_next;
    reg [ADDR_WIDTH:0] rd_ptr_gray, rd_ptr_gray_next;
    reg [ADDR_WIDTH:0] rd_ptr_binary, rd_ptr_binary_next;
    reg [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    reg [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;
    reg [7:0]          fifo_mem [0:FIFO_DEPTH-1];
    reg                 full_flag;
    reg                 empty_flag;
    reg                 overflow_flag;
    reg                 underflow_flag;
    
    // Write pointer management (in write clock domain)
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_binary <= 0;
            wr_ptr_gray <= 0;
        end else if (wr_enable && wr_valid && !full_flag) begin
            wr_ptr_binary_next = wr_ptr_binary + 1;
            wr_ptr_binary <= wr_ptr_binary_next;
            // Convert to gray code
            wr_ptr_gray_next = wr_ptr_binary_next;
            wr_ptr_gray_next = wr_ptr_gray_next ^ (wr_ptr_gray_next >> 1);
            wr_ptr_gray <= wr_ptr_gray_next;
            
            // Write data to FIFO
            fifo_mem[wr_ptr_binary[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end
    
    // Read pointer management (in read clock domain)
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_binary <= 0;
            rd_ptr_gray <= 0;
        end else if (rd_enable && rd_read_enable && !empty_flag) begin
            rd_ptr_binary_next = rd_ptr_binary + 1;
            rd_ptr_binary <= rd_ptr_binary_next;
            // Convert to gray code
            rd_ptr_gray_next = rd_ptr_binary_next;
            rd_ptr_gray_next = rd_ptr_gray_next ^ (rd_ptr_gray_next >> 1);
            rd_ptr_gray <= rd_ptr_gray_next;
        end
    end
    
    // Synchronize write pointer to read clock domain
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_ptr_gray_sync1 <= 0;
            wr_ptr_gray_sync2 <= 0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end
    
    // Synchronize read pointer to write clock domain
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end
    
    // Full/empty flag calculation
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            full_flag <= 0;
            empty_flag <= 1;
            overflow_flag <= 0;
            underflow_flag <= 0;
        end else begin
            // Convert synchronized write pointer back to binary for comparison
            reg [ADDR_WIDTH:0] wr_ptr_binary_sync;
            wr_ptr_binary_sync = wr_ptr_gray_sync2;
            wr_ptr_binary_sync = wr_ptr_binary_sync ^ (wr_ptr_binary_sync >> 2);
            wr_ptr_binary_sync = wr_ptr_binary_sync ^ (wr_ptr_binary_sync >> 1);
            
            // Empty condition: pointers are equal
            empty_flag <= (rd_ptr_gray == wr_ptr_gray_sync2);
            
            // Underflow detection (read when empty)
            if (rd_read_enable && empty_flag) begin
                underflow_flag <= 1;
            end
        end
    end
    
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            full_flag <= 0;
        end else begin
            // Convert synchronized read pointer back to binary for comparison
            reg [ADDR_WIDTH:0] rd_ptr_binary_sync;
            rd_ptr_binary_sync = rd_ptr_gray_sync2;
            rd_ptr_binary_sync = rd_ptr_binary_sync ^ (rd_ptr_binary_sync >> 2);
            rd_ptr_binary_sync = rd_ptr_binary_sync ^ (rd_ptr_binary_sync >> 1);
            
            // Full condition: next write would make pointers point to same location
            full_flag <= ((wr_ptr_binary[ADDR_WIDTH-1:0] == rd_ptr_binary_sync[ADDR_WIDTH-1:0]) &&
                         (wr_ptr_binary[ADDR_WIDTH] != rd_ptr_binary_sync[ADDR_WIDTH]));
            
            // Overflow detection (write when full)
            if (wr_valid && full_flag) begin
                overflow_flag <= 1;
            end
        end
    end
    
    // Output assignments
    assign rd_data = fifo_mem[rd_ptr_binary[ADDR_WIDTH-1:0]];
    assign rd_valid = rd_enable && !empty_flag;
    assign full = full_flag;
    assign empty = empty_flag;
    assign overflow = overflow_flag;
    assign underflow = underflow_flag;

endmodule