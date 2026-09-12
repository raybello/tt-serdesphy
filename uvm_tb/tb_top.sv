// Top-level simulation entry point: instantiates system_if and
// test_harness/system.sv (the DUT + bus wiring), publishes the
// virtual interface to the UVM environment, and starts UVM.

`timescale 1ns / 1ps

module tb_top;

  import uvm_pkg::*;
`include "uvm_macros.svh"

  import serdesphy_pkg::*;

  system_if vif ();

  system u_system (.vif(vif));

  // No-op unless the binary was built with tracing (build.py's
  // default): scripts/run.py runs each test from its own directory,
  // so this lands as <run dir>/waves.vcd.
  initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, tb_top);
  end

  initial begin
    serdesphy_report_server report_server;

    // Report timestamps (UVM's "@ <time>") always in ns, regardless of
    // this module's 1ps precision - otherwise they print as raw
    // simulation steps (i.e. picoseconds).
    $timeformat(-9, 3, " ns", 1);

    // Shortens the absolute file paths UVM prints in every report line
    // - see test_harness/report_server.sv. Must be installed before
    // run_test() so it's in place for the very first report.
    report_server = new("serdesphy_report_server");
    uvm_report_server::set_server(report_server);

    uvm_config_db#(virtual system_if)::set(null, "*", "vif", vif);
    run_test();
  end

endmodule : tb_top
