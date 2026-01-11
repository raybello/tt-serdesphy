
interface serdesphy_if (
    input logic clk,
    reset
);

    //---------------------------------------
    //declaring the signals
    //---------------------------------------
    logic [1:0] addr;
    logic wr_en;
    logic rd_en;
    logic [7:0] wdata;
    logic [7:0] rdata;

endinterface
