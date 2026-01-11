
`include "sys_if.sv"
`include "serdesphy_if.sv"
`include "serdesphy_pkg.sv"


module serdesphy_system;

    import uvm_pkg::*;
    import serdesphy_pkg::*;

    bit clk;  // external signal declaration
    bit reset_n;

    //----------------------------------------------------------------------------
    serdesphy_if dut_if (
        clk,
        reset_n
    );
    sys_if sys_if ();
    //----------------------------------------------------------------------------

    //----------------------------------------------------------------------------
    // Device Under Test
    //----------------------------------------------------------------------------
    memory dut (
        .clk  (sys_if.clk),
        .reset(sys_if.rst_n),
        .addr (dut_if.addr),
        .wr_en(dut_if.wr_en),
        .rd_en(dut_if.rd_en),
        .wdata(dut_if.wdata),
        .rdata(dut_if.rdata)
    );
    //----------------------------------------------------------------------------               

    initial begin
        clk = 0;
        reset_n = 1;
        #2 reset_n = 0;
        #10 reset_n = 1;
    end

    always #5 clk = ~clk;

    //----------------------------------------------------------------------------
    initial begin
        $dumpfile("dumpfile.vcd");
        $dumpvars;
    end
    //----------------------------------------------------------------------------

    //----------------------------------------------------------------------------
    initial begin
        uvm_config_db#(virtual sys_if)::set(null, "*", "sys_vi", sys_if);
        uvm_config_db#(virtual serdesphy_if)::set(uvm_root::get(), "*", "dut_vif", dut_if);
    end
    //----------------------------------------------------------------------------

    //----------------------------------------------------------------------------
    initial begin
        run_test();
    end
    //----------------------------------------------------------------------------

endmodule
