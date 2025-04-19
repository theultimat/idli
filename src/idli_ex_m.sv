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
  input  var sqi_data_t i_ex_imm,

  // Current and next PC of the instruction in decode and whether the
  // instruction executing is redirecting the PC.
  input  var sqi_data_t i_ex_pc,
  input  var sqi_data_t i_ex_pc_next,
  output var logic      o_ex_redirect,

  // ALU output for transferring data to the rest of the core.
  output var sqi_data_t o_ex_alu_out,

  // Current instruction that's executing and how far through we are.
  output var op_t         o_ex_op,
  output var logic        o_ex_op_vld,
  output var logic [1:0]  o_ex_ctr,

  // Interface to the UART.
  input  var sqi_data_t i_ex_uart_rx,
  output var logic      o_ex_uart_tx_vld,
  output var logic      o_ex_uart_rx_acp
);

  // Track progress through the instruction using a 2b counter. We process 16b
  // over four cycles.
  logic [1:0] ctr_q;

  // Flopped value of the instruction to execute.
  op_t  op_q;
  logic op_vld_q;
  logic op_vld_d;

  // Data read from the register file.
  sqi_data_t  lhs_reg_data;
  sqi_data_t  rhs_reg_data;

  // Write signals for register file.
  greg_t      wr_reg;
  logic       wr_reg_en;
  sqi_data_t  wr_reg_data;

  // LHS and RHS of operations.
  sqi_data_t  lhs_data;
  sqi_data_t  rhs_data;

  // Saved carry to feed back on subsequent cycles.
  logic carry_q;
  logic carry_d;
  logic alu_cin;
  logic alu_sign_cin;

  // ALU output.
  sqi_data_t alu_out;

  // Predicate register file signals.
  preg_t  wr_pred;
  logic   wr_pred_en;
  logic   wr_pred_data;
  logic   rd_pred_data;

  // Flags based on ALU output. We have the same flags as ARM: Zero, Negative,
  // Carry, and oVerflow. These can all be detected on the final cycle except
  // for Z which needs to record whether each generated output slice is zero.
  logic flag_z_q;
  logic flag_z;
  logic flag_n;
  logic flag_c;
  logic flag_v;

`ifdef idli_debug_signals_d

  // These signals are used in the test bench for debug and synchronising with
  // the behavioural model.
  logic instr_done;
  logic instr_skip;

`endif // idli_debug_signals_d


  // General purpose register file.
  idli_regs_m regs_u (
    .i_reg_gck      (i_ex_gck),

    .i_reg_lhs      (op_q.b),
    .o_reg_lhs_data (lhs_reg_data),
    .i_reg_rhs      (op_q.c),
    .o_reg_rhs_data (rhs_reg_data),

    .i_reg_wr       (wr_reg),
    .i_reg_wr_en    (wr_reg_en),
    .i_reg_wr_data  (wr_reg_data)
  );

  // Predicate register file.
  idli_preds_m preds_u (
    .i_pred_gck     (i_ex_gck),

    .i_pred_rd      (i_ex_op.p),
    .o_pred_rd_data (rd_pred_data),

    .i_pred_wr      (wr_pred),
    .i_pred_wr_en   (wr_pred_en),
    .i_pred_wr_data (wr_pred_data)
  );

  // ALU.
  idli_alu_m alu_u (
    .i_alu_gck      (i_ex_gck),

    .i_alu_op       (op_q.alu_op),
    .i_alu_rhs_inv  (op_q.alu_rhs_inv),

    .i_alu_lhs      (lhs_data),
    .i_alu_rhs      (rhs_data),
    .i_alu_cin      (alu_cin),

    .o_alu_data     (alu_out),
    .o_alu_cout     (carry_d),
    .o_alu_sign_cin (alu_sign_cin)
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
      op_vld_q <= op_vld_d;
    end
  end

  // When we're accepting an instruction it's only going to be valid if the
  // predicate is true - this is why we feed the incoming instruction's P into
  // the register file rather than the flopped value.
  always_comb op_vld_d = i_ex_op_vld && rd_pred_data && !o_ex_redirect;

  // Determine what the value for operands should be based on the routing
  // information decoded from the instruction.
  always_comb begin
    case (op_q.lhs_src)
      LHS_SRC_REG:  lhs_data = lhs_reg_data;
      LHS_SRC_ZERO: lhs_data = '0;
      LHS_SRC_PC:   lhs_data = i_ex_pc;
      default:      lhs_data = sqi_data_t'('x);
    endcase
  end

  always_comb begin
    case (op_q.rhs_src)
      RHS_SRC_REG:  rhs_data = rhs_reg_data;
      RHS_SRC_IMM:  rhs_data = i_ex_imm;
      RHS_SRC_UART: rhs_data = i_ex_uart_rx;
      default:      rhs_data = sqi_data_t'('x);
    endcase
  end

  // Carry in comes from the operation on the first cycle and the previous
  // output on all other cycles.
  always_comb alu_cin = |ctr_q ? carry_q : op_q.alu_cin;

  // Save carry of previous cycle on output.
  always_ff @(posedge i_ex_gck) begin
    if (op_vld_q && ctr_q != 2'd3) begin
      carry_q <= carry_d;
    end
  end

  // Write the output of the ALU into A if it's valid, but override with the
  // next PC if LR should be written instead.
  always_comb wr_reg      = op_q.wr_lr ? GREG_LR : op_q.a;
  always_comb wr_reg_en   = op_vld_q && (op_q.a_vld || op_q.wr_lr);
  always_comb wr_reg_data = op_q.wr_lr ? i_ex_pc_next : alu_out;

  // Write into the predicate register if Q is valid.
  always_comb wr_pred       = op_q.q;
  always_comb wr_pred_en    = op_vld_q && op_q.q_vld;

  always_comb begin
    case (op_q.cmp_op)
      CMP_OP_EQ: wr_pred_data =  flag_z;
      CMP_OP_NE: wr_pred_data = ~flag_z;
      CMP_OP_LT: wr_pred_data = op_q.cmp_signed ? (flag_n != flag_v) : ~flag_c;
      default:   wr_pred_data = op_q.cmp_signed ? (flag_n == flag_v) :  flag_c;
    endcase
  end

  // Redirect if we're writing the PC.
  always_comb o_ex_redirect = op_vld_q && op_q.wr_pc;

  // Forward the ALU output and op etc.
  always_comb o_ex_alu_out = alu_out;
  always_comb o_ex_op      = op_q;
  always_comb o_ex_op_vld  = op_vld_q;
  always_comb o_ex_ctr     = ctr_q;

  // UART TX is valid depending on the counter - the low 8b is sent on the
  // first two instruction cycles, and the high on the final two.
  always_comb o_ex_uart_tx_vld = op_vld_q && (op_q.uart_tx_lo && !ctr_q[1]
                                          ||  op_q.uart_tx_hi &&  ctr_q[1]);

  // UART RX should be accepted on URX or URXB.
  always_comb o_ex_uart_rx_acp = op_vld_q && (op_q.uart_rx_lo && !ctr_q[1]
                                          ||  op_q.uart_rx_hi &&  ctr_q[1]);

  // Reset the persistent Z flag on reset or when the next cycle will be the
  // first of an instruction, otherwise flop the new value.
  always_ff @(posedge i_ex_gck, negedge i_ex_rst_n) begin
    if (!i_ex_rst_n) begin
      flag_z_q <= '1;
    end else if (op_vld_q) begin
      flag_z_q <= &ctr_q ? '1 : flag_z;
    end
  end

  // New value to flop for Z is determined by the current output of the ALU
  // all begin zero, as well as all the previous cycles also being zero.
  always_comb flag_z = flag_z_q && ~|alu_out;

  // N is set if the highest bit of the output is set.
  always_comb flag_n = alu_out[3];

  // C is set directly from the carry out of the ALU.
  always_comb flag_c = carry_d;

  // V is set based on the bit carry out and carry in of the sign bit of the
  // ALU output being different.
  always_comb flag_v = alu_sign_cin ^ carry_d;

`ifdef idli_debug_signals_d

  always_comb instr_done = op_vld_q && ctr_q == 2'd3;
  always_comb instr_skip = i_ex_op_vld && !rd_pred_data;

`endif // idli_debug_signals_d

endmodule
