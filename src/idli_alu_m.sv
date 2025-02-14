`include "idli_pkg.svh"


// 4b serial ALU, processes 16b in four cycles.
module idli_alu_m import idli_pkg::*; (
  // Clock - no reset.
  input  var logic  i_alu_gck,

  // Control signals.
  input  var alu_op_t     i_alu_op,
  input  var logic        i_alu_rhs_inv,

  // Input data.
  input  var sqi_data_t i_alu_lhs,
  input  var sqi_data_t i_alu_rhs,
  input  var logic      i_alu_cin,

  // Output data.
  output var sqi_data_t o_alu_data,
  output var logic      o_alu_cout
);

  sqi_data_t  alu_add;
  sqi_data_t  alu_and;
  sqi_data_t  alu_xor;
  sqi_data_t  alu_or;
  sqi_data_t  alu_rhs;

  // Optionally invert RHS.
  always_comb alu_rhs = i_alu_rhs_inv ? ~i_alu_rhs : i_alu_rhs;

  // Compute logical operations.
  always_comb alu_and = i_alu_lhs & alu_rhs;
  always_comb alu_xor = i_alu_lhs ^ alu_rhs;
  always_comb alu_or  = i_alu_rhs | alu_rhs;

  // Reuse the AND and XOR to compute the ADD.
  always_comb begin
    logic carry;

    carry = i_alu_cin;

    for (int unsigned BIT = 0; BIT < 4; BIT++) begin
      alu_add[BIT] = alu_xor[BIT] ^ carry;
      carry = (alu_xor[BIT] & carry) | alu_and[BIT];
    end

    o_alu_cout = carry;
  end

  // Select final output based on operation.
  always_comb begin
    case (i_alu_op)
      ALU_OP_ADD: o_alu_data = alu_add;
      ALU_OP_AND: o_alu_data = alu_and;
      ALU_OP_OR:  o_alu_data = alu_or;
      default:    o_alu_data = alu_xor;
    endcase
  end

endmodule
