

`ifndef SERDESPHY_ENV_CONFIG
`define SERDESPHY_ENV_CONFIG

class serdesphy_env_config extends uvm_object;
    `uvm_object_utils(serdesphy_env_config)

    rand sys_config sys_cfg;

    function new(string name = "serdesphy_env_config");
        super.new(name);
    endfunction

endclass
`endif
