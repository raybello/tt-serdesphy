// Drives clk_ref_24m and dut_rst_n onto system_if.
//
// START_CLK spawns a background toggling thread (killed by a
// subsequent STOP_CLK or a new START_CLK); ASSERT_RST/DEASSERT_RST
// drive dut_rst_n directly. DEASSERT_RST waits rst_assert_cycles
// clk_ref_24m edges (falling back to a plain time delay if the clock
// isn't running yet) before releasing reset.

class clk_reset_driver extends uvm_driver #(clk_reset_tr);

  `uvm_component_utils(clk_reset_driver)

  virtual system_if vif;
  protected bit      clk_running = 1'b0;

  function new(string name = "clk_reset_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual system_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "clk_reset_driver: virtual interface not set via uvm_config_db")
  endfunction

  task run_phase(uvm_phase phase);
    clk_reset_tr item;

    vif.clk_ref_24m = 1'b0;
    vif.dut_rst_n   = 1'b1;

    forever begin
      seq_item_port.get_next_item(item);

      case (item.kind)

        CLK_RESET_ASSERT_RST: begin
          vif.dut_rst_n = 1'b0;
          `uvm_info("CLK_RESET_DRV", "Reset asserted", UVM_HIGH)
        end

        CLK_RESET_DEASSERT_RST: begin
          if (clk_running) begin
            repeat (item.rst_assert_cycles) @(posedge vif.clk_ref_24m);
          end else begin
            #(item.rst_assert_cycles * item.clk_period_ps * 1ps);
          end
          vif.dut_rst_n = 1'b1;
          `uvm_info("CLK_RESET_DRV",
                     $sformatf("Reset deasserted after %0d cycle(s)", item.rst_assert_cycles),
                     UVM_HIGH)
        end

        CLK_RESET_START_CLK: begin
          start_clk(item.clk_period_ps, item.duty_cycle_pct, item.jitter_ps);
          `uvm_info("CLK_RESET_DRV",
                     $sformatf("Clock started: period=%0dps duty=%0d%% jitter=%0dps",
                                item.clk_period_ps, item.duty_cycle_pct, item.jitter_ps),
                     UVM_HIGH)
        end

        CLK_RESET_STOP_CLK: begin
          stop_clk();
          `uvm_info("CLK_RESET_DRV", "Clock stopped", UVM_HIGH)
        end

        default: `uvm_fatal("CLK_RESET_DRV", "Unknown clk_reset_tr kind")

      endcase

      seq_item_port.item_done();
    end
  endtask : run_phase

  // Spawns (replacing any existing) background clock-toggling thread.
  task automatic start_clk(int unsigned period_ps, int unsigned duty_pct, int unsigned jitter_ps);
    disable clk_gen_blk;
    clk_running = 1'b1;
    fork
      begin : clk_gen_blk
        int unsigned high_ps, low_ps;
        int          jit;
        forever begin
          high_ps = (period_ps * duty_pct) / 100;
          low_ps  = (period_ps > high_ps) ? (period_ps - high_ps) : 0;
          if (jitter_ps > 0) begin
            jit     = $urandom_range(jitter_ps, 0) - int'(jitter_ps / 2);
            high_ps = (jit < 0 && (-jit) > high_ps) ? high_ps : high_ps + jit;
          end
          vif.clk_ref_24m = 1'b1;
          #(high_ps * 1ps);
          vif.clk_ref_24m = 1'b0;
          #(low_ps * 1ps);
        end
      end
    join_none
  endtask : start_clk

  function void stop_clk();
    disable clk_gen_blk;
    clk_running     = 1'b0;
    vif.clk_ref_24m = 1'b0;
  endfunction : stop_clk

endclass : clk_reset_driver
