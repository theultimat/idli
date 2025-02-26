`include "idli_pkg.svh"


// This module keeps all the other modlues synchronised with each other, with
// the main idea being to gate off the clocks.
// TODO Instance actual gating cells when we have a cell library.
module idli_sync_m import idli_pkg::*; (
  // Clock and reset.
  input  var logic  i_sync_gck,
  input  var logic  i_sync_rst_n,

  // Control signals from the rest of the core.
  input  var op_t         i_sync_dcd_op,
  input  var logic        i_sync_dcd_op_vld,
  input  var logic        i_sync_ex_op_acp,
  input  var op_t         i_sync_ex_op,
  input  var logic        i_sync_ex_op_vld,
  input  var logic [1:0]  i_sync_ex_ctr,
  input  var logic        i_sync_uart_tx_acp,

  // Gated clock signal.
  output var logic  o_sync_gck
);

  // Gate signal for the output clock.
  logic gate_q;
  logic gate_d;


  // Execution units need to be stalled in the following scenarios:
  // - UART TX instruction but UART is busy.
  always_comb begin
    gate_d = '1;

    if (i_sync_dcd_op_vld && i_sync_ex_op_acp) begin
      // If we're accepting then we need to check for new instruction stall
      // conditions.
      if (i_sync_dcd_op.uart_tx_lo) begin
        gate_d = i_sync_uart_tx_acp;
      end
    end else if (i_sync_ex_op_vld) begin
      // We're part way through an instruction but may need to stall because
      // the input or output is stalled.
      if (i_sync_ex_op.uart_tx_hi && i_sync_ex_ctr == 2'd1) begin
        gate_d = i_sync_uart_tx_acp;
      end
    end
  end

  // Flop gate signals on the negative edge.
  always_ff @(negedge i_sync_gck, negedge i_sync_rst_n) begin
    if (!i_sync_rst_n) begin
      gate_q <= '1;
    end else begin
      gate_q <= gate_d;
    end
  end

  // Output the gated clock.
  always_comb o_sync_gck = i_sync_gck && gate_q;

endmodule
