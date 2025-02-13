`include "idli_pkg.svh"


// Execution units and logic.
module idli_ex_m import idli_pkg::*; (
  // Clock and reset.
  input  var logic  i_ex_gck,
  input  var logic  i_ex_rst_n,

  // Decoded instruction and whether we can accept a new one.
  input  var op_t   i_ex_op,
  input  var logic  i_ex_op_vld,
  output var logic  o_ex_op_acp,

  // Immedaite data read from the memory.
  input  var sqi_data_t i_ex_imm
);

  // Track progress through the instruction using a 2b counter. We process 16b
  // over four cycles.
  logic [1:0] ctr_q;

  // Flopped value of the instruction to execute.
  op_t  op_q;
  logic op_vld_q;

  // Data read from the register file.
  sqi_data_t  b_reg_data;
  sqi_data_t  c_reg_data;

  // LHS and RHS of operations.
  sqi_data_t  b_data;
  sqi_data_t  c_data;


  // General purpose register file.
  idli_regs_m regs_u (
    .i_reg_gck    (i_ex_gck),

    .i_reg_b      (op_q.b),
    .o_reg_b_data (b_reg_data),
    .i_reg_c      (op_q.c),
    .o_reg_c_data (c_reg_data)
  );

  // ALU.
  idli_alu_m alu_u (
    .i_alu_gck      (i_ex_gck),

    .i_alu_op       (op_q.alu_op),
    .i_alu_rhs_inv  ('0), // TODO
    .i_alu_ctr      (ctr_q),

    .i_alu_lhs      (b_data),
    .i_alu_rhs      (c_data),
    .i_alu_cin      ('0),   // TODO

    // verilator lint_off PINCONNECTEMPTY
    .o_alu_data     (),
    .o_alu_cout     ()
    // verilator lint_on PINCONNECTEMPTY
  );


  // Increment the counter when the instruction is valid.
  always_ff @(posedge i_ex_gck, negedge i_ex_rst_n) begin
    if (!i_ex_rst_n) begin
      ctr_q <= '0;
    end else if (op_vld_q) begin
      ctr_q <= ctr_q + 2'd1;
    end
  end

  // For now always accept an incoming instruction if this is the final cycle
  // or we don't have anything currently executing.
  always_comb o_ex_op_acp = !op_vld_q || &ctr_q;

  // Accept an incoming instruction.
  always_ff @(posedge i_ex_gck, negedge i_ex_rst_n) begin
    if (!i_ex_rst_n) begin
      op_q     <= 'x;
      op_vld_q <= '0;
    end else if (o_ex_op_acp) begin
      op_q     <= i_ex_op;
      op_vld_q <= i_ex_op_vld;
    end
  end

  // Determine what the value for operands should be based on the routing
  // information decoded from the instruction.
  always_comb begin
    case (op_q.b_src)
      B_SRC_REG:  b_data = b_reg_data;
      B_SRC_ZERO: b_data = '0;
      B_SRC_PC:   b_data = '0;            // TODO PC not implemented yet.
      default:    b_data = sqi_data_t'('x);
    endcase
  end

  always_comb begin
    case (op_q.c_src)
      C_SRC_REG:  c_data = c_reg_data;
      C_SRC_IMM:  c_data = i_ex_imm;
      default:    c_data = sqi_data_t'('x);
    endcase
  end

endmodule
