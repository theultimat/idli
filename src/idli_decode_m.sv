`include "idli_pkg.svh"


// Decodes instructions 4b per cycle.
module idli_decode_m import idli_pkg::*; (
  // Clock and resert.
  input  var logic  i_dcd_gck,
  input  var logic  i_dcd_rst_n,

  // Instruction encoding and whether it's valid.
  input  var sqi_data_t i_dcd_enc,
  input  var logic      i_dcd_enc_vld
);

  // As the instruction is decoded 4b per cycle we have a state machine to
  // remember our progress.
  typedef enum logic [4:0] {
    // First decode cycle.
    STATE_INIT,

    // Second decode cycle.
    STATE_NOP_BZ,
    STATE_EQ_LT,
    STATE_GE_PUTP_CMPZ,
    STATE_SRX,
    STATE_ROR_SLL,
    STATE_MEM_WB,
    STATE_MEM,
    STATE_STACK_PERM_INV_INC_URX_0,
    STATE_ADD_SUB,
    STATE_AND_ANDN,
    STATE_OR_XOR,
    STATE_MOV_PC_BP_JP_UTX,

    // Third decode cyle.
    STATE_NOP_0,
    STATE_BZ,
    STATE_QBC,
    STATE_CMPZ_PUTP_0,
    STATE_ABC,
    STATE_STACK_PERM_INV_INC_URX_1,
    STATE_BP_JP_UTX,
    STATE_MOV_PC,

    // Final decode cycle.
    STATE_NOP_1,
    STATE_BC,
    STATE_CMPZ_PUTP_1,
    STATE_STACK_PERM_INV_INC_URX_2
  } state_t;

  // Current and next state for the decoder.
  state_t state_q;
  state_t state_d;

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
        // We don't have anymore operation bits yet so keep going into the
        // next cycle.
        state_d = STATE_STACK_PERM_INV_INC_URX_1;
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
      STATE_ABC,
      STATE_MOV_PC,
      STATE_BP_JP_UTX: begin
        // We're now fully decoded so parse B and C operands.
        state_d = STATE_BC;
      end
      STATE_CMPZ_PUTP_0: begin
        // No more opcode bits in this cycle so keep going.
        state_d = STATE_CMPZ_PUTP_1;
      end
      STATE_STACK_PERM_INV_INC_URX_1: begin
        // No more opcode bits, continue.
        state_d = STATE_STACK_PERM_INV_INC_URX_2;
      end
      default: begin
        // All states return back to the start for the next instruction.
        state_d = STATE_INIT;
      end
    endcase
  end

endmodule
