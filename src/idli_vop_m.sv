// B??Z B, C  ->  ??Z    TMP, B   # REUSE STICKY CARRY FLAG FOR RESULT?
//            ->  BT.TMP C

// LD.P A, B, C ->  ADD.P ADDR, B, C
//              ->  ADD.P A, SQI, 0
// ST.P A, B, C ->  ADD.P ADDR, B, C
//              ->  ADD.P SQI, A, 0

// !LD.P A, B, C  ->  ADD.P (ADDR, B), B, C
//                ->  ADD.P A, SQI, 0
// !ST.P A, B, C  ->  ADD.P (ADDR, B), B, C
//                ->  ADD.P SQI, A, 0

// LD!.P A, B, C  ->  ADD.P B, (ADDR <- B), C
//                ->  ADD.P A, SQI, 0
// ST!.P A, B, C  ->  ADD.P B, (ADDR <- B), C
//                ->  ADD.P SQI, A, 0

// PUSH REGS  -> SUB (ADDR, SP), SP, POPCNT(REGS)
//            -> ADD SQI, NEXT(REGS), 0
//
// POP REGS   -> ADD SP, (ADDR <- SP), POPCNT(REGS)
//            -> ADD NEXT(REGS), SQI, 0

`include "idli_pkg.svh"


// Handles "virtual" operations by splitting the decoded operation into one or
// more standard operations.
module idli_vop_m import idli_pkg::*; (
  // Clock and reset.
  input  var logic  i_vop_gck,
  input  var logic  i_vop_rst_n,

  // Encoding coming from the SQI memories.
  input  var sqi_data_t i_vop_enc,
  input  var logic      i_vop_enc_vld,

  // Interface to decoder.
  input  var vop_type_t   i_vop_type,
  input  var logic        i_vop_type_vld,
  input  var logic [1:0]  i_vop_ctr,
  input  var logic        i_vop_stack,

  // Interface to execute.
  output var op_t   o_vop_op,
  output var logic  o_vop_op_vld
);

  // Templates for the various instruction types.
  localparam OP_LD = op_t'{
    p:            preg_t'('x),
    q:            preg_t'('x),
    a:            greg_t'('x),
    b:            greg_t'('x),
    c:            greg_t'('x),
    q_vld:        '0,
    a_vld:        '1,
    b_vld:        'x,
    c_vld:        'x,
    lhs_src:      LHS_SRC_SQI,
    rhs_src:      RHS_SRC_ZERO,
    alu_op:       ALU_OP_ADD,
    alu_cin:      '0,
    alu_rhs_inv:  '0,
    wr_pc:        '0,
    wr_lr:        '0,
    uart_tx_lo:   '0,
    uart_tx_hi:   '0,
    uart_rx_lo:   '0,
    uart_rx_hi:   '0,
    cmp_op:       cmp_op_t'('x),
    cmp_signed:   'x,
    p_inv:        '0,
    wr_sqi:       '0
  };

  localparam op_t OP_ST = op_t'{
    p:            preg_t'('x),
    q:            preg_t'('x),
    a:            greg_t'('x),
    b:            greg_t'('x),
    c:            greg_t'('x),
    q_vld:        '0,
    a_vld:        '0,
    b_vld:        'x,
    c_vld:        'x,
    lhs_src:      LHS_SRC_REG,
    rhs_src:      RHS_SRC_ZERO,
    alu_op:       ALU_OP_ADD,
    alu_cin:      '0,
    alu_rhs_inv:  '0,
    wr_pc:        '0,
    wr_lr:        '0,
    uart_tx_lo:   '0,
    uart_tx_hi:   '0,
    uart_rx_lo:   '0,
    uart_rx_hi:   '0,
    cmp_op:       cmp_op_t'('x),
    cmp_signed:   'x,
    p_inv:        '0,
    wr_sqi:       '1
  };

  // Every four cycles we need to generate a new instruction to be consumed by
  // the execution units or indicate we're done. For loads and stores this is
  // determined by whether or not there are any registers left in the mask.
  typedef enum logic [2:0] {
    STATE_IDLE,
    STATE_LD,
    STATE_ST,
    STATE_LD_STACK,
    STATE_ST_STACK
  } state_t;

  // Current and next state.
  state_t state_q;
  state_t state_d;

  // Saved register state. This is a bitmap of enabled registers for stack ops
  // or the A, B, C operands for other ops.
  logic [8:0] regs_q;
  logic [8:0] regs_d;

  // Whether the decoder is currently generating the first instruction of
  // a vop. This allows us to capture the incoming SQI state for processing.
  logic dcd_active_q;

  // Predicate register used on the original instruction.
  preg_t preg_q;


  // Flop the next state or reset back to idle. We only need to flop a new
  // state when the counter is one as this is the cycle when decode presents
  // us enough information to get going.
  always_ff @(posedge i_vop_gck, negedge i_vop_rst_n) begin
    if (!i_vop_rst_n) begin
      state_q <= STATE_IDLE;
    end else if (i_vop_ctr == 2'd1) begin
      state_q <= state_d;
    end
  end

  // Determine the next state.
  always_comb begin
    state_d = state_q;

    case (state_q)
      STATE_IDLE: begin
        // If we have a valid VOP incoming then check its type to move to the
        // next appropriate state.
        if (i_vop_type_vld) begin
          case (i_vop_type)
            VOP_TYPE_LD: state_d = i_vop_stack ? STATE_LD_STACK : STATE_LD;
            VOP_TYPE_ST: state_d = i_vop_stack ? STATE_ST_STACK : STATE_ST;
            default:     state_d = state_q; // TODO BZ
          endcase
        end
      end
      default: begin
        // TODO
        state_d = state_q;
      end
    endcase
  end

  // Decoder is active on first cycle of operation i.e. when the incoming vop
  // type is valid and the state is still idle. After this point we reset back
  // to zero when the incoming instruction ends.
  always_ff @(posedge i_vop_gck) begin
    if (i_vop_type_vld && state_q == STATE_IDLE) begin
      dcd_active_q <= i_vop_enc_vld;
    end else if (i_vop_ctr == 2'd3) begin
      dcd_active_q <= '0;
    end
  end

  // Determine which bits to flop into the register storage.
  always_comb begin
    regs_d = regs_q;

    // On first cycle of vop flop the incoming register state.
    if (i_vop_type_vld || dcd_active_q) begin
      case (i_vop_ctr)
        2'd1:    regs_d[8]   = i_vop_enc[0];
        2'd2:    regs_d[7:4] = i_vop_enc;
        default: regs_d[3:0] = i_vop_enc;
      endcase
    end

    // TODO clear bits for stack ops
  end

  // Flop new register state.
  always_ff @(posedge i_vop_gck) begin
    regs_q <= regs_d;
  end

  // Flop predicate register on first cycle of the op.
  always_ff @(posedge i_vop_gck) begin
    if (i_vop_type_vld && state_q == STATE_IDLE) begin
      preg_q <= preg_t'(i_vop_enc[2:1]);
    end
  end

  // Output the new vop based on the current state.
  always_comb begin
    o_vop_op     = op_t'('x);
    o_vop_op_vld = '0;

    case (state_q)
      STATE_LD: begin
        o_vop_op   = OP_LD;
        o_vop_op.p = preg_q;
        o_vop_op.a = greg_t'(regs_q[8:6]);

        o_vop_op_vld = '1;
      end
      STATE_ST: begin
        o_vop_op   = OP_ST;
        o_vop_op.p = preg_q;
        o_vop_op.b = greg_t'(regs_q[5:3]);

        o_vop_op_vld = '1;
      end
      default: begin
        // TODO
      end
    endcase
  end

endmodule
