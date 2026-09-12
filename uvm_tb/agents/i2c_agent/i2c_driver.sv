// Bit-bangs I2C write/read CSR transactions onto system_if (see
// docs/info.md section 6.2 for the wire format and I2C_DEV_ADDR /
// 0x42 for the device address). Single master, no clock stretching:
// scl is driven only by this driver.
//
// BIT_PERIOD (2us => 500 kHz) comfortably clears both the DUT's I2C
// spec minimum (t_LOW/t_HIGH >= 0.5us) and its internal debounce
// window (DEB_I2C_LEN = 5 clk_ref_24m cycles, ~208ns @ 24MHz).

class i2c_driver extends uvm_driver #(i2c_tr);

  `uvm_component_utils(i2c_driver)

  virtual system_if vif;

  local const realtime BIT_PERIOD = 2us;

  function new(string name = "i2c_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual system_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "i2c_driver: virtual interface not set via uvm_config_db")
  endfunction

  task run_phase(uvm_phase phase);
    i2c_tr item;

    vif.scl               = 1'b1;
    vif.mst_sda_drive_low = 1'b0;

    forever begin
      seq_item_port.get_next_item(item);

      case (item.kind)
        I2C_WRITE_REG: do_write(item.reg_addr, item.wdata, item.status);
        I2C_READ_REG:  do_read(item.reg_addr, item.rdata, item.status);
        default:       `uvm_fatal("I2C_DRV", "Unknown i2c_tr kind")
      endcase

      `uvm_info("I2C_DRV",
                 $sformatf("%s addr=0x%0h wdata=0x%0h rdata=0x%0h status=%0b",
                            item.kind.name(), item.reg_addr, item.wdata, item.rdata, item.status),
                 UVM_HIGH)

      seq_item_port.item_done();
    end
  endtask : run_phase

  // ------------------------------------------------------------------
  // Bus-level primitives
  // ------------------------------------------------------------------

  // Drives (drive_en=1) or samples (drive_en=0) sda over one clock
  // pulse. `bit_val` is only used when driving: 0 pulls sda low,
  // 1 releases it (relies on the DUT's own pull when it wants to
  // drive, else the wired-AND default-high in system_if).
  task automatic clock_bit(input bit drive_en, input bit bit_val, output bit sampled);
    vif.scl = 1'b0;
    vif.mst_sda_drive_low = drive_en ? (bit_val == 1'b0) : 1'b0;
    #(BIT_PERIOD / 2);
    vif.scl = 1'b1;
    #(BIT_PERIOD / 4);
    sampled = vif.sda;
    #(BIT_PERIOD / 4);
  endtask : clock_bit

  task automatic i2c_start();
    // Force SCL low and hold it first: after an ACK the DUT keeps
    // driving SDA low until its own FSM sees SCL low and releases it
    // (a few clk_ref_24m cycles later). Signalling START (SDA falling
    // while SCL is high) before that release has happened means SDA
    // was never actually high to begin with, so no edge - and no
    // START - is seen. This mirrors the settle margin in recv_byte.
    vif.scl               = 1'b0;
    vif.mst_sda_drive_low = 1'b0;
    #(BIT_PERIOD / 2);
    vif.scl = 1'b1;  // bus now idle high
    #(BIT_PERIOD / 4);
    vif.mst_sda_drive_low = 1'b1;  // SDA falls while SCL high
    #(BIT_PERIOD / 2);
    vif.scl = 1'b0;
    #(BIT_PERIOD / 2);
  endtask : i2c_start

  task automatic i2c_stop();
    vif.scl               = 1'b0;
    vif.mst_sda_drive_low = 1'b1;
    #(BIT_PERIOD / 2);
    vif.scl = 1'b1;
    #(BIT_PERIOD / 2);
    vif.mst_sda_drive_low = 1'b0;  // SDA rises while SCL high
    #(BIT_PERIOD / 2);
  endtask : i2c_stop

  task automatic send_byte(input bit [7:0] data, output bit ackd);
    bit sampled;
    for (int i = 7; i >= 0; i--) clock_bit(1'b1, data[i], sampled);
    clock_bit(1'b0, 1'b0, sampled);  // release for ACK/NAK
    ackd = ~sampled;                 // ACK == 0
  endtask : send_byte

  task automatic recv_byte(output bit [7:0] data, input bit send_ack);
    bit sampled;
    data = '0;
    // Extra SCL-low settle time before the first bit: the DUT's
    // address-match -> STREAM_READ -> first txData load takes a
    // handful of clk_ref_24m cycles (through its debounce/delay
    // pipeline) to complete after the address byte's ACK. Without
    // this margin the first bit can be sampled one bit-period early,
    // shifting the whole byte down by one bit.
    vif.scl = 1'b0;
    #(BIT_PERIOD / 2);
    for (int i = 7; i >= 0; i--) begin
      clock_bit(1'b0, 1'b0, sampled);
      data[i] = sampled;
    end
    clock_bit(1'b1, ~send_ack, sampled);  // master drives ACK(0)/NAK(1)
  endtask : recv_byte

  task automatic do_write_once(input bit [7:0] reg_addr, input bit [7:0] wdata, output bit ok);
    bit ack_addr, ack_reg, ack_data;
    i2c_start();
    send_byte({system_pkg::I2C_DEV_ADDR, 1'b0}, ack_addr);
    send_byte(reg_addr, ack_reg);
    send_byte(wdata, ack_data);
    i2c_stop();
    ok = ack_addr && ack_reg && ack_data;
  endtask : do_write_once

  task automatic do_read_once(input bit [7:0] reg_addr, output bit [7:0] rdata, output bit ok);
    bit ack_addr_w, ack_reg, ack_addr_r;
    i2c_start();
    send_byte({system_pkg::I2C_DEV_ADDR, 1'b0}, ack_addr_w);
    send_byte(reg_addr, ack_reg);
    i2c_start();  // repeated START
    send_byte({system_pkg::I2C_DEV_ADDR, 1'b1}, ack_addr_r);
    recv_byte(rdata, 1'b0);  // single-byte read: master NAKs
    i2c_stop();
    ok = ack_addr_w && ack_reg && ack_addr_r;
  endtask : do_read_once

  // do_write_once()/do_read_once() occasionally see a NACK on the very
  // first transaction after the bus has been idle since reset - a
  // one-off race between this bit-banger and the DUT's debounce/edge
  // detectors landing exactly on a clk_ref_24m edge. Retry a few times
  // (with a bus-idle recovery gap) before reporting failure, the way a
  // real I2C master would after a lost-arbitration/NACK.
  local const int unsigned MAX_RETRIES = 3;
  local const realtime     RETRY_IDLE  = 5us;

  task automatic do_write(input bit [7:0] reg_addr, input bit [7:0] wdata, output bit ok);
    for (int unsigned attempt = 0; attempt < MAX_RETRIES; attempt++) begin
      do_write_once(reg_addr, wdata, ok);
      if (ok) return;
      `uvm_warning("I2C_DRV", $sformatf("write to 0x%0h NACKed, retrying (attempt %0d)", reg_addr, attempt + 1))
      #(RETRY_IDLE);
    end
  endtask : do_write

  task automatic do_read(input bit [7:0] reg_addr, output bit [7:0] rdata, output bit ok);
    for (int unsigned attempt = 0; attempt < MAX_RETRIES; attempt++) begin
      do_read_once(reg_addr, rdata, ok);
      if (ok) return;
      `uvm_warning("I2C_DRV", $sformatf("read from 0x%0h NACKed, retrying (attempt %0d)", reg_addr, attempt + 1))
      #(RETRY_IDLE);
    end
  endtask : do_read

endclass : i2c_driver
