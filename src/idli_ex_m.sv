`include "idli_pkg.svh"


// Execution units and logic.
module idli_ex_m import idli_pkg::*; (
  // Clock and reset.
  input  var logic  i_ex_gck,
  input  var logic  i_ex_rst_n,

  // Decoded instruction and whether we can accept a new one.
  input  var op_t   i_ex_op,
  input  var logic  i_ex_op_vld,
  output var logic  o_ex_op_acp
);

  // Track progress through the instruction using a 2b counter. We process 16b
  // over four cycles.
  logic [1:0] ctr_q;

  // Flopped value of the instruction to execute.
  op_t  op_q;
  logic op_vld_q;

  // Data read from the register file.
  sqi_data_t  b_data;
  sqi_data_t  c_data;


  // General purpose register file.
  idli_regs_m regs_u (
    .i_reg_gck    (i_ex_gck),

    .i_reg_b      (op_q.b),
    .o_reg_b_data (b_data),
    .i_reg_c      (op_q.c),
    .o_reg_c_data (c_data)
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

endmodule
