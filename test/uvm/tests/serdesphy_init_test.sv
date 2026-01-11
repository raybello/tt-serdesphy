
class serdesphy_init_test extends serdesphy_base_test;

    `uvm_component_utils(serdesphy_init_test)

    

    //---------------------------------------
    // constructor
    //---------------------------------------
    function new(string name = "serdesphy_init_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    //---------------------------------------
    // build_phase
    //---------------------------------------
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        configure_sys_env();
    endfunction : build_phase

    //---------------------------------------
    // configure_sys_env
    //---------------------------------------
    function void configure_sys_env();
      super.configure_sys_env();

      if (!env_config.randomize())
         `uvm_fatal(tID, "env_config Failed to Randomize")
      else begin
         `uvm_info(tID, $sformatf("%s", env_config.sys_cfg.convert2string()), UVM_LOW)
      end
   endfunction

    //---------------------------------------
    // run_phase - starting the test
    //---------------------------------------
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info(get_type_name(), $sformatf("------ :: STARTING TEST :: ------"), UVM_LOW)
        super.run_phase(phase);
        `uvm_info(get_type_name(), $sformatf("------ :: FINISHED TEST :: ------"), UVM_LOW)
        phase.drop_objection(this);

    endtask : run_phase

endclass : serdesphy_init_test
