
`ifndef SYS_DRIVER
`define SYS_DRIVER

class sys_driver extends uvm_driver #(sys_trans, sys_trans);
    `uvm_component_utils(sys_driver)

    sys_config cfg;

    function new(string name = "sys_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
    endfunction

    task run_phase(uvm_phase phase);
        `uvm_info(get_type_name(), "Driver run_phase started", UVM_LOW)
        cfg.sys_vi.pins = cfg.pins;
        get_and_drive();
    endtask

    task get_and_drive();
        forever begin
            sys_trans req_item, rsp_item;

            `uvm_info(get_type_name(), "Driver waiting for item...", UVM_HIGH)
            seq_item_port.get_next_item(req_item);
            `uvm_info(get_type_name(), $sformatf("Driver got item: start_clk=%0d, assert_rst=%0d", req_item.start_clk, req_item.assert_rst), UVM_MEDIUM)

            if (req_item.start_clk) begin
                `uvm_info(get_type_name(), "Starting clock", UVM_MEDIUM)
                start_clk();
            end
            if (req_item.assert_rst) begin
                `uvm_info(get_type_name(), "Asserting reset", UVM_MEDIUM)
                assert_rst();
            end
            seq_item_port.item_done();
            `uvm_info(get_type_name(), "Item done", UVM_HIGH)
        end
    endtask

    task start_clk();
        real clk_period;

        clk_period = (1 / cfg.clk_freq) * 1000000;  //ps

        fork
            forever begin
                cfg.sys_vi.clk = 1'b0;
                #(clk_period * (100 - cfg.clk_duty_cycle) / 100.0);
                cfg.sys_vi.clk = 1'b1;
                #(clk_period * cfg.clk_duty_cycle / 100.0);
            end
        join_none
    endtask

    task assert_rst();
        cfg.sys_vi.rst_n = 1'b0;
        for (int i = 0; i < cfg.rst_assert; i++) #1ns;
        cfg.sys_vi.rst_n = 1'b1;
        for (int i = 0; i < cfg.post_rst; i++) #1ns;
    endtask

endclass
`endif
