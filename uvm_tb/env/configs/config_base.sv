// Base configuration object shared by every agent's config class.
// Just carries the standard is_active knob; agent-specific configs
// extend this and add their own knobs/constraints.

class config_base extends uvm_object;

  uvm_active_passive_enum is_active = UVM_ACTIVE;

  `uvm_object_utils_begin(config_base)
    `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "config_base");
    super.new(name);
  endfunction

endclass : config_base
