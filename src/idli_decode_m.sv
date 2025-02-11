`include "idli_pkg.svh"


// Decodes instructions 4b per cycle.
module idli_decode_m import idli_pkg::*; (
  // Clock and resert.
  input  var logic  i_dcd_gck,
  input  var logic  i_dcd_rst_n,

  // Instruction encoding and whether it's valid.
  input  var sqi_data_t i_dcd_enc,
  input  var logic      i_dcd_enc_vld,

  // Decoded instruction and whether it's valid.
  output var op_t   o_dcd_op,
  output var logic  o_dcd_op_vld
);

  // As the instruction is decoded 4b per cycle we have a state machine to
  // remember our progress. Which cycle of decode we're currently in is
  // encoded in the top 2b of the state.
  typedef enum logic [5:0] {
    // First decode cycle.
    STATE_INIT                      = 6'b000000,

    // Second decode cycle.
    STATE_NOP_BZ                    = 6'b010000,
    STATE_EQ_LT                     = 6'b010001,
    STATE_GE_PUTP_CMPZ              = 6'b010010,
    STATE_SRX                       = 6'b010011,
    STATE_ROR_SLL                   = 6'b010100,
    STATE_MEM_WB                    = 6'b010101,
    STATE_MEM                       = 6'b010110,
    STATE_STACK_PERM_INV_INC_URX_0  = 6'b010111,
    STATE_ADD_SUB                   = 6'b011000,
    STATE_AND_ANDN                  = 6'b011001,
    STATE_OR_XOR                    = 6'b011010,
    STATE_MOV_PC_BP_JP_UTX          = 6'b011011,

    // Third decode cyle.
    STATE_NOP_0                     = 6'b100000,
    STATE_BZ                        = 6'b100001,
    STATE_QBC                       = 6'b100010,
    STATE_CMPZ_PUTP_0               = 6'b100011,
    STATE_ABC                       = 6'b100100,
    STATE_STACK_PERM_INV_0          = 6'b100101,
    STATE_INC_URX_0                 = 6'b100110,
    STATE_BP_JP_UTX                 = 6'b100111,
    STATE_MOV_PC                    = 6'b101000,

    // Final decode cycle.
    STATE_NOP_1                     = 6'b110000,
    STATE_BC                        = 6'b110001,
    STATE_C                         = 6'b110010,
    STATE_CMPZ_PUTP_1               = 6'b110011,
    STATE_STACK_PERM_INV_1          = 6'b110100,
    STATE_INC_URX_1                 = 6'b110101
  } state_t;

  // Current and next state for the decoder.
  state_t state_q;
  state_t state_d;

  // Which cycle of the decode operation we're currently on.
  logic [1:0] cycle_q;

  // Decoded operation state. We need the flopped form to hold the decoded
  // state while we process the rest of the instruction and the non-flopped
  // form is output on the final cycle to be flopped by the backend.
  op_t op_q;
  op_t op_d;

  // Flop the new state.
  always_ff @(posedge i_dcd_gck, negedge i_dcd_rst_n) begin
    if (!i_dcd_rst_n) begin
      state_q <= STATE_INIT;
    end else begin
      state_q <= state_d;
    end
  end

  // Determine the next state.
  always_comb begin
    state_d = state_q;

    case (state_q)
      STATE_INIT: begin
        // If the encoding is valid then we have a new instruction so start
        // decoding the first bits.
        if (i_dcd_enc_vld) begin
          casez (i_dcd_enc)
            4'b0000: state_d = STATE_NOP_BZ;
            4'b0100: state_d = STATE_EQ_LT;
            4'b0101: state_d = STATE_GE_PUTP_CMPZ;
            4'b0110: state_d = STATE_SRX;
            4'b0111: state_d = STATE_ROR_SLL;
            4'b100?: state_d = STATE_MEM_WB;
            4'b1010: state_d = STATE_MEM;
            4'b1011: state_d = STATE_STACK_PERM_INV_INC_URX_0;
            4'b1100: state_d = STATE_ADD_SUB;
            4'b1101: state_d = STATE_AND_ANDN;
            4'b1110: state_d = STATE_OR_XOR;
            4'b1111: state_d = STATE_MOV_PC_BP_JP_UTX;
            default: state_d = state_t'('x);
          endcase
        end
      end
      STATE_NOP_BZ: begin
        // If the bottom bit of the entry is a 1 then we have a conditional
        // branch checking register against zero, otherwise it must be a NOP.
        state_d = i_dcd_enc[0] ? STATE_BZ : STATE_NOP_0;
      end
      STATE_EQ_LT: begin
        // We've fully decoded whether it's EQ/NE/LT/LTU now so all that's
        // left is to read the operands.
        state_d = STATE_QBC;
      end
      STATE_GE_PUTP_CMPZ: begin
        // GE[U] and PUTP can now be fully decoded, so we just need to read
        // the operands, but comparisons against zero and PUTP[TF] need
        // further decoding.
        casez (i_dcd_enc)
          4'b1??1: state_d = STATE_CMPZ_PUTP_0;
          default: state_d = STATE_QBC;
        endcase
      end
      STATE_STACK_PERM_INV_INC_URX_0: begin
        // Top bit being set indicates this is INC/DEC/URX[B].
        state_d = i_dcd_enc[3] ? STATE_INC_URX_0 : STATE_STACK_PERM_INV_0;
      end
      STATE_SRX,
      STATE_ROR_SLL,
      STATE_MEM_WB,
      STATE_MEM,
      STATE_ADD_SUB,
      STATE_AND_ANDN,
      STATE_OR_XOR: begin
        // We know the operation so just read all the operands.
        state_d = STATE_ABC;
      end
      STATE_MOV_PC_BP_JP_UTX: begin
        // If the highest bit is clear then we have an A operand, and if not
        // then it's a branch or jump or UTX.
        state_d = i_dcd_enc[3] ? STATE_BP_JP_UTX : STATE_MOV_PC;
      end
      STATE_NOP_0: begin
        // Nothing more to do.
        state_d = STATE_NOP_1;
      end
      STATE_BZ,
      STATE_QBC,
      STATE_ABC: begin
        // We're now fully decoded so parse B and C operands.
        state_d = STATE_BC;
      end
      STATE_MOV_PC,
      STATE_BP_JP_UTX: begin
        // Only parsing of C remains.
        state_d = STATE_C;
      end
      STATE_CMPZ_PUTP_0: begin
        // No more opcode bits in this cycle so keep going.
        state_d = STATE_CMPZ_PUTP_1;
      end
      STATE_STACK_PERM_INV_0: begin
        // No more opcode bits, continue.
        state_d = STATE_STACK_PERM_INV_1;
      end
      STATE_INC_URX_0: begin
        // No more opcode bits, continue.
        state_d = STATE_INC_URX_1;
      end
      default: begin
        // All states return back to the start for the next instruction.
        state_d = STATE_INIT;
      end
    endcase
  end

  // Extract the current cycle from the state.
  always_comb cycle_q = state_q[5:4];

  // Extract operand values during decode. These are always in the same
  // location so can be extracted based on the current cycle regardless of
  // which instruction is being processed. Having more accurate enables would
  // probably improve power but we aren't too concerned about that here.
  always_comb begin
    op_d.p = op_q.p;
    op_d.q = op_q.q;
    op_d.a = op_q.a;
    op_d.b = op_q.b;
    op_d.c = op_q.c;

    if (cycle_q == 2'd1) begin
        op_d.a[2] = i_dcd_enc[0];

        // Special case here for P - all instructions except NOP and branch
        // and compare on register are predicated, with these two special
        // cases always forced to be PT.
        if (state_q == STATE_NOP_BZ) begin
          op_d.p = PREG_PT;
        end else begin
          op_d.p = preg_t'(i_dcd_enc[2:1]);
        end
    end else if (cycle_q == 2'd2) begin
        op_d.q      = preg_t'(i_dcd_enc[3:2]);
        op_d.a[1:0] = i_dcd_enc[3:2];
        op_d.b[2:1] = i_dcd_enc[1:0];
    end else if (cycle_q == 2'd3) begin
        op_d.b[0] = i_dcd_enc[3];
        op_d.c    = greg_t'(i_dcd_enc[2:0]);
    end
  end

  // Flop the new value of the instruction - this needs to be done on all
  // cycles except the final one as we output the non-flopped version anyway.
  always_ff @(posedge i_dcd_gck) begin
    if (i_dcd_enc_vld && cycle_q != 2'd3) begin
      op_q <= op_d;
    end
  end

  // Operand A is always known to be valid on decode cycle two.
  always_comb begin
    op_d.a_vld = op_q.a_vld;

    if (cycle_q == 2'd2) begin
      op_d.a_vld = state_q == STATE_ABC
                || state_q == STATE_STACK_PERM_INV_0
                || state_q == STATE_INC_URX_0
                || state_q == STATE_MOV_PC;
      end
  end

  // We can only be sure if B is valid on the final cycle of decode.
  always_comb begin
    op_d.b_vld = op_q.b_vld;

    if (cycle_q == 2'd3) begin
      case (state_q)
        STATE_BC:               op_d.b_vld = '1;
        STATE_STACK_PERM_INV_1: op_d.b_vld = '1;
        STATE_INC_URX_1:        op_d.b_vld = ~i_dcd_enc[1];
        default:                op_d.b_vld = '0;
      endcase
    end
  end

  // C is decoded on the final cycle so we must know it's valid when we get
  // there.
  always_comb begin
    op_d.c_vld = op_q.c_vld;

    if (cycle_q == 2'd3) begin
      op_d.c_vld = state_q == STATE_BC
                || state_q == STATE_C;
    end
  end

  // Output the _d of the decoded op so it can be flopped immediately in
  // execute.
  always_comb o_dcd_op = op_d;

  // Instruction is valid if we're in a final state, unless it's a NOP as
  // these can just be thrown away in decode.
  always_comb o_dcd_op_vld = (cycle_q == 2'd3) && state_q != STATE_NOP_1;

  // Determine where to take operand B from.
  always_comb begin
    case (state_q)
      STATE_ABC:    op_d.b_src = B_SRC_REG;
      STATE_MOV_PC: op_d.b_src = i_dcd_enc[0] ? B_SRC_PC : B_SRC_ZERO;
      default:      op_d.b_src = op_q.b_src;
    endcase
  end

  // C is always read from the register unless it's the immediate.
  always_comb op_d.c_src = &i_dcd_enc[2:0] ? C_SRC_IMM : C_SRC_REG;

  // Determine the ALU operation to execute.
  always_comb begin
    case (state_q)
      STATE_ADD_SUB:          op_d.alu_op = ALU_OP_ADD;
      STATE_AND_ANDN:         op_d.alu_op = ALU_OP_AND;
      STATE_OR_XOR:           op_d.alu_op = i_dcd_enc[3] ? ALU_OP_XOR : ALU_OP_OR;
      STATE_MOV_PC_BP_JP_UTX: op_d.alu_op = ALU_OP_ADD;
      default:                op_d.alu_op = op_q.alu_op;
    endcase
  end

endmodule
