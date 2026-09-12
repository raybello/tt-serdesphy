class clk_reset_assert_rst_seq extends uvm_sequence #(clk_reset_tr);

  `uvm_object_utils(clk_reset_assert_rst_seq)

  function new(string name = "clk_reset_assert_rst_seq");
    super.new(name);
  endfunction

  task body();
    clk_reset_tr item = clk_reset_tr::type_id::create("item");
    start_item(item);
    item.kind = CLK_RESET_ASSERT_RST;
    finish_item(item);
  endtask : body

endclass : clk_reset_assert_rst_seq
