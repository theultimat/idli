`include "idli_pkg.svh"


// This module keeps all the other modlues synchronised with each other, with
// the main idea being to gate off the clocks.
// TODO Instance actual gating cells when we have a cell library.
module idli_sync_m import idli_pkg::*; (
  // Clock and reset.
  input  var logic  i_sync_gck,
  input  var logic  i_sync_rst_n,

  // Control signals from the rest of the core.
  input  var op_t   i_sync_dcd_op,
  input  var logic  i_sync_dcd_op_vld,
  input  var logic  i_sync_ex_op_acp,
  input  var logic  i_sync_uart_tx_acp,

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

    // Check EX is going to accept a new instruction.
    if (i_sync_dcd_op_vld && i_sync_ex_op_acp) begin
      // We're accepting so check the stall conditions.
      if (i_sync_dcd_op.uart_tx_lo || i_sync_dcd_op.uart_tx_hi) begin
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
