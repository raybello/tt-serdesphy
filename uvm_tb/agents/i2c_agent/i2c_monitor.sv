// Passively watches system_if.scl/sda and reconstructs the I2C byte
// stream: detects START/STOP framing and broadcasts one i2c_tr per
// byte seen on the bus (reg_addr field reused to carry the raw byte,
// status carries the ACK/NAK bit). This is a best-effort bus sniffer
// for debug/coverage - i2c_driver's own do_write()/do_read() results
// remain the source of truth for pass/fail.

class i2c_monitor extends uvm_monitor;

  `uvm_component_utils(i2c_monitor)

  virtual system_if vif;
  uvm_analysis_port #(i2c_tr) ap;

  function new(string name = "i2c_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual system_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "i2c_monitor: virtual interface not set via uvm_config_db")
  endfunction

  task run_phase(uvm_phase phase);
    bit          synced = 1'b0;
    bit [7:0]    shift;
    int unsigned bit_cnt;

    fork
      // START/STOP framing detector
      begin
        bit sda_prev = 1'b1;
        bit scl_prev = 1'b1;
        forever begin
          @(vif.sda or vif.scl);
          if (vif.scl && scl_prev) begin
            if (sda_prev && !vif.sda) begin
              `uvm_info("I2C_MON", "START condition", UVM_HIGH)
              synced  = 1'b1;
              bit_cnt = 0;
            end else if (!sda_prev && vif.sda) begin
              `uvm_info("I2C_MON", "STOP condition", UVM_HIGH)
              synced = 1'b0;
            end
          end
          sda_prev = vif.sda;
          scl_prev = vif.scl;
        end
      end

      // Byte sampler: on every scl rising edge while synced, shift in
      // one bit; every 9th bit is ACK/NAK, completing one byte.
      begin
        forever begin
          @(posedge vif.scl);
          if (synced) begin
            if (bit_cnt < 8) begin
              shift   = {shift[6:0], vif.sda};
              bit_cnt++;
            end else begin
              i2c_tr tr = i2c_tr::type_id::create("bus_byte");
              tr.reg_addr = shift;
              tr.status   = ~vif.sda;  // ACK == 0
              ap.write(tr);
              `uvm_info("I2C_MON",
                         $sformatf("byte=0x%0h ack=%0b", shift, tr.status),
                         UVM_HIGH)
              bit_cnt = 0;
            end
          end
        end
      end
    join
  endtask : run_phase

endclass : i2c_monitor
