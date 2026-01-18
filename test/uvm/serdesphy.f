# Compile list for serdesphy
# Project defines
+define+UVM_ENABLE_DEPRECATED_API
+define+UVM_NO_DPI

# Folder includes
+incdir+./agents/sys_uvc
+incdir+./agents/sys_uvc/seqs
+incdir+./common/sim/shared
+incdir+./env
+incdir+./env/configs
+incdir+./seq
+incdir+./tests
+incdir+./top
+incdir+./hdl

# UVC packages
./agents/sys_uvc/sys_if.sv
./agents/sys_uvc/sys_uvc_pkg.sv

# Common packages
./common/sim/shared/common_pkg.sv

# Environment packages
./env/serdesphy_env_pkg.sv

# Sequence packages
./seq/serdesphy_seq_pkg.sv

# Test packages
./tests/serdesphy_test_pkg.sv

# Top level module
./top/serdesphy_system.sv

# Test initiator
./common/sim/shared/test_initiator.sv

# RTL design files
./hdl/design.sv
