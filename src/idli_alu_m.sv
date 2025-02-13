`include "idli_pkg.svh"


// 4b serial ALU, processes 16b in four cycles.
module idli_alu_m import idli_pkg::*; (
  // Clock - no reset.
  input  var logic  i_alu_gck,

  // Control signals.
  input  var alu_op_t     i_alu_op,
  input  var logic        i_alu_rhs_inv,
  input  var logic [1:0]  i_alu_ctr,

  // Input data.
  input  var sqi_data_t i_alu_lhs,
  input  var sqi_data_t i_alu_rhs,
  input  var logic      i_alu_cin,

  // Output data.
  output var sqi_data_t o_alu_data,
  output var logic      o_alu_cout
);

  for (genvar BIT = 0; BIT < 4; BIT++) begin : num_bits_b
  end : num_bits_b

endmodule
