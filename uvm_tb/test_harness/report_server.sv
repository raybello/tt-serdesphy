// Custom uvm_report_server: shortens the absolute file paths UVM
// prints in every report line (e.g. "UVM_INFO <path>(<line>) @ ...")
// down to something readable, by overriding compose_report_message -
// the documented Accellera extension point for report formatting
// (see uvm_report_server.svh). Installed globally in tb_top before
// run_test() via uvm_report_server::set_server().

import uvm_pkg::*;

class serdesphy_report_server extends uvm_default_report_server;

  // Known absolute path roots to collapse: the UVM library lives in a
  // third-party checkout entirely outside this repo, and our own
  // sources live under the repo root - both print as long absolute
  // paths otherwise.
  local static string uvm_src_prefix =
      "/Users/raybello/Github/verilator-verification/third-party/sv-tests/third_party/tests/uvm/src/";
  local static string repo_prefix = "/Users/raybello/Github/tt-serdesphy/";

  function new(string name = "serdesphy_report_server");
    super.new(name);
  endfunction

  local static function string shorten_filename(string s);
    if (s.len() >= uvm_src_prefix.len() && s.substr(0, uvm_src_prefix.len() - 1) == uvm_src_prefix)
      return {"uvm/", s.substr(uvm_src_prefix.len(), s.len() - 1)};
    if (s.len() >= repo_prefix.len() && s.substr(0, repo_prefix.len() - 1) == repo_prefix)
      return s.substr(repo_prefix.len(), s.len() - 1);
    return s;
  endfunction : shorten_filename

  virtual function string compose_report_message(uvm_report_message report_message,
                                                  string report_object_name = "");
    report_message.set_filename(shorten_filename(report_message.get_filename()));
    return super.compose_report_message(report_message, report_object_name);
  endfunction : compose_report_message

endclass : serdesphy_report_server
