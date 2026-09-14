// Partial filelist for the test_harness/ sources. Included from the
// top-level uvm_tb/filelist.f via `-f`; must be read before checkers/
// and before serdesphy_pkg.sv (system_pkg::* and system_if are used
// by both).
//
// Uses the @@REPO_ROOT@@ placeholder token - see uvm_tb/filelist.f.

+incdir+@@REPO_ROOT@@/uvm_tb/test_harness

@@REPO_ROOT@@/uvm_tb/test_harness/defines.sv
@@REPO_ROOT@@/uvm_tb/test_harness/system_pkg.sv
@@REPO_ROOT@@/uvm_tb/test_harness/system_if.sv
@@REPO_ROOT@@/uvm_tb/test_harness/report_server.sv
@@REPO_ROOT@@/uvm_tb/checkers/clk_checker.sv
@@REPO_ROOT@@/uvm_tb/checkers/reset_checker.sv
@@REPO_ROOT@@/uvm_tb/test_harness/binds.sv
@@REPO_ROOT@@/uvm_tb/test_harness/system.sv
