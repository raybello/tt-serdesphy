package common_pkg;
   `include "uvm_macros.svh"
   import uvm_pkg::*;

   `define DISPLAY_PASS $display("%c[1;32m\nTest PASSED\n\n%c[0m",27,27);
   `define DISPLAY_FAIL $display("%c[1;31m\nTest FAILED\n\n%c[0m",27,27);

endpackage
