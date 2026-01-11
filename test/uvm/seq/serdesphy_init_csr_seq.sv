
`ifndef SERDESPHY_INIT_CSR_SEQ
`define SERDESPHY_INIT_CSR_SEQ

class serdesphy_init_csr_seq extends serdesphy_base_seq;

    `uvm_object_utils(serdesphy_init_csr_seq)

    //---------------------------------------
    //  Declaring sequences
    //---------------------------------------
    // write_sequence wr_seq;

    //---------------------------------------
    //Constructor
    //---------------------------------------
    function new(string name = "serdesphy_init_csr_seq");
        super.new(name);
    endfunction

    //---------------------------------------
    // create, randomize and send the item to driver
    //---------------------------------------

    virtual task body();
        `uvm_info(get_type_name(), "CSR SEQ BODY STARTED", UVM_LOW)
        super.body();
        `uvm_info(get_type_name(), $sformatf("------ :: STARTING CSR INIT :: ------"), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("Writing to CSRs..."), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("------ :: FINISHED CSR INIT :: ------"), UVM_LOW)
    endtask
endclass
//=========================================================================
`endif
