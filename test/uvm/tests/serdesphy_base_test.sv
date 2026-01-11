
class serdesphy_base_test extends uvm_test;

    `uvm_component_utils(serdesphy_base_test)

    string                 tID;

    //---------------------------------------
    // env instance
    //---------------------------------------
    serdesphy_env          env;
    serdesphy_env_config   env_config;

    //---------------------------------------
    // sequence instance
    //---------------------------------------
    serdesphy_init_csr_seq init_seq;

    //---------------------------------------
    // constructor
    //---------------------------------------
    function new(string name = "serdesphy_base_test", uvm_component parent = null);
        super.new(name, parent);
        tID = get_name();
        tID = tID.toupper();
    endfunction : new

    //---------------------------------------
    // build_phase
    //---------------------------------------
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Create the env
        env = serdesphy_env::type_id::create("env", this);
        // Create the sequence
        init_seq = serdesphy_init_csr_seq::type_id::create("init_seq");

        // Configure the environment
        configure_sys_env();

        // Set the watchdog timer - do not change the value here, override in testcase.
        // uvm_action.set_timeout(1000000000);  //1M ns

    endfunction : build_phase

    //---------------------------------------
    // run_phase
    //---------------------------------------
    task run_phase(uvm_phase phase);
        super.run_phase(phase);
        init_seq.start(null);
    endtask

    //---------------------------------------
    // end_of_elaboration phase
    //---------------------------------------
    virtual function void end_of_elaboration();
        //print's the topology
        print();
    endfunction

    //---------------------------------------
    // report_phase
    //---------------------------------------
    function void report_phase(uvm_phase phase);
        uvm_report_server svr;
        super.report_phase(phase);

        svr = uvm_report_server::get_server();
        if (svr.get_severity_count(UVM_FATAL) + svr.get_severity_count(UVM_ERROR) > 0) begin
            `uvm_info(get_type_name(), "---------------------------------------", UVM_NONE)
            `uvm_info(get_type_name(), "----            TEST FAIL          ----", UVM_NONE)
            `uvm_info(get_type_name(), "---------------------------------------", UVM_NONE)
        end else begin
            `uvm_info(get_type_name(), "---------------------------------------", UVM_NONE)
            `uvm_info(get_type_name(), "----           TEST PASS           ----", UVM_NONE)
            `uvm_info(get_type_name(), "---------------------------------------", UVM_NONE)
        end
    endfunction

    //---------------------------------------
    // configure_sys_env
    //---------------------------------------
    function void configure_sys_env();
        env_config = serdesphy_env_config::type_id::create("env_config", this);
        env_config.sys_cfg = new("env_config.sys_cfg");

        // env_config.axim_agt_cfg = axi_agent_config#(ID_WIDTH, ADDR_WIDTH, BYTE_WIDTH, USER_WIDTH)::type_id::create(
        //     "env_config.axim_agt_cfg", this);
        // env_config.axis_agt_cfg = axi_agent_config#(ID_WIDTH, ADDR_WIDTH, BYTE_WIDTH, USER_WIDTH)::type_id::create(
        //     "env_config.axis_agt_cfg", this);

        env_config.sys_cfg.clk_freq = 250;
        env_config.sys_cfg.clk_duty_cycle = 50;
        env_config.sys_cfg.rst_assert = 20;
        env_config.sys_cfg.post_rst = 20;

        // env_config.axim_agt_cfg.active = UVM_ACTIVE;
        // env_config.axim_agt_cfg.master = 1;

        assert (uvm_config_db#(virtual sys_if)::get(this, "", "sys_vi", env_config.sys_cfg.sys_vi))
        else `uvm_error(tID, "Failed to find sys_vi")
        // assert (uvm_config_db#(virtual axi_if)::get(
        //     this, "", "axi_vi", env_config.axim_agt_cfg.axi_vi
        // ))
        // else `uvm_error(tID, "Failed to find axi_vi")
        // assert (uvm_config_db#(virtual axi_if)::get(
        //     this, "", "axi_vi", env_config.axis_agt_cfg.axi_vi
        // ))
        // else `uvm_error(tID, "Failed to find axi_vi")

        env.phy_env_cfg      = this.env_config;
        init_seq.phy_env_cfg = this.env_config;
    endfunction


endclass : serdesphy_base_test
