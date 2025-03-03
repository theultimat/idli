`include "idli_pkg.svh"


// This module keeps all the other modlues synchronised with each other, with
// the main idea being to gate off the clocks.
// TODO Instance actual gating cells when we have a cell library.
module idli_sync_m import idli_pkg::*; (
  // Clock and reset.
  input  var logic  i_sync_gck,
  input  var logic  i_sync_rst_n,

  // Control signals from the rest of the core.
  input  var op_t         i_sync_ex_op,
  input  var logic        i_sync_ex_op_vld,
  input  var logic [1:0]  i_sync_ex_ctr,
  input  var logic        i_sync_uart_tx_acp,
  input  var logic        i_sync_uart_rx_vld,

  // Gated clock signal.
  output var logic  o_sync_gck
);

  // Gate signal for the output clock.
  logic gate_q;

  // Single bit for each stall reason.
  logic [3:0] stall;

  // Whether this is the first cycle of an instruction
  logic ex_new;

  // EX counter cycles.
  logic ex_ctr_0;
  logic ex_ctr_2;


  // Accepting a UART TX then need to stall if the UART isn't accepting any
  // new incoming data.
  always_comb stall[0] = ex_new && i_sync_ex_op.uart_tx_lo
                                && ~i_sync_uart_tx_acp;

  // UART TX high bit uses the same logic but on a different EX cycle.
  always_comb stall[1] = ex_ctr_2 && i_sync_ex_op.uart_tx_hi
                                  && ~i_sync_uart_tx_acp;

  // Low UART RX can only be read out when we have 8b available in the buffer.
  always_comb stall[2] = ex_new && i_sync_ex_op.uart_rx_lo
                                && ~i_sync_uart_rx_vld;

  // High UART RX is the same but on the correct cycle in EX.
  always_comb stall[3] = ex_ctr_2 && i_sync_ex_op.uart_rx_hi
                                  && ~i_sync_uart_rx_vld;


  // EX is starting a new instruction this cycle.
  always_comb ex_new = i_sync_ex_op_vld && ex_ctr_0;

  // Whether the EX counter is a certain cycle and execution is valid.
  always_comb ex_ctr_0 = i_sync_ex_op_vld && i_sync_ex_ctr == '0;
  always_comb ex_ctr_2 = i_sync_ex_op_vld && i_sync_ex_ctr == 2'd2;


  // Gate is the negated OR of all the possible stall reasons.
  always_ff @(negedge i_sync_gck, negedge i_sync_rst_n) begin
    if (!i_sync_rst_n) begin
      gate_q <= '1;
    end else begin
      gate_q <= ~|stall;
    end
  end

  // Output the gated clock.
  always_comb o_sync_gck = i_sync_gck && gate_q;

endmodule
