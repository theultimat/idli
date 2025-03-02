`include "idli_pkg.svh"


// UART TX and RX.
module idli_uart_m import idli_pkg::*; (
  // Clock and reset.
  input  var logic  i_uart_gck,
  input  var logic  i_uart_rst_n,

  // RX interface.
  input  var logic      i_uart_rx,
  output var logic      o_uart_rx_vld,
  input  var logic      i_uart_rx_acp,
  output var sqi_data_t o_uart_rx,

  // TX interface.
  input  var sqi_data_t i_uart_tx,
  input  var logic      i_uart_tx_vld,
  output var logic      o_uart_tx_acp,
  output var logic      o_uart_tx,

  // Whether a new instruction is being accepted by EX.
  input  var logic      i_uart_ex_op_acp
);

  // Simple state machine for both RX and TX.
  typedef enum logic [3:0] {
    STATE_IDLE,
    STATE_START,
    STATE_DATA_0,
    STATE_DATA_1,
    STATE_DATA_2,
    STATE_DATA_3,
    STATE_DATA_4,
    STATE_DATA_5,
    STATE_DATA_6,
    STATE_DATA_7,
    STATE_RX_OUT_0,
    STATE_RX_OUT_1
  } state_t;

  // Current and next state for transmission.
  state_t tx_state_q;
  state_t tx_state_d;
  state_t rx_state_q;
  state_t rx_state_d;

  // Shift register for TX data.
  logic [7:0] tx_data_q;

  // Shift register for RX data.
  logic [7:0] rx_data_q;

  // Whether RX data is being accepted this cycle.
  logic rx_acp;


  // Flop the next states.
  always_ff @(posedge i_uart_gck, negedge i_uart_rst_n) begin
    if (!i_uart_rst_n) begin
      tx_state_q <= STATE_IDLE;
      rx_state_q <= STATE_IDLE;
    end else begin
      tx_state_q <= tx_state_d;
      rx_state_q <= rx_state_d;
    end
  end

  // Determine the next state for TX. We wait in IDLE until we see data valid
  // at which point we transition to START. This means we accept the first 4b
  // in IDLE, the next 4b in START, and can then transmit the values each bit
  // at a time.
  always_comb begin
    case (tx_state_q)
      STATE_IDLE:   tx_state_d = i_uart_tx_vld ? STATE_START : STATE_IDLE;
      STATE_START:  tx_state_d = STATE_DATA_0;
      STATE_DATA_0: tx_state_d = STATE_DATA_1;
      STATE_DATA_1: tx_state_d = STATE_DATA_2;
      STATE_DATA_2: tx_state_d = STATE_DATA_3;
      STATE_DATA_3: tx_state_d = STATE_DATA_4;
      STATE_DATA_4: tx_state_d = STATE_DATA_5;
      STATE_DATA_5: tx_state_d = STATE_DATA_6;
      STATE_DATA_6: tx_state_d = STATE_DATA_7;
      default:      tx_state_d = STATE_IDLE;
    endcase
  end

  // Data incoming from the core is valid on IDLE or START at 4b per cycle,
  // otherwise rotate the register at 1b per cycle.
  always_ff @(posedge i_uart_gck) begin
    if (tx_state_q == STATE_IDLE || tx_state_q == STATE_START) begin
      tx_data_q <= {i_uart_tx, tx_data_q[7:4]};
    end else begin
      tx_data_q <= {tx_data_q[0], tx_data_q[7:1]};
    end
  end

  // Only accept a new batch of data if we're IDLE.
  always_comb o_uart_tx_acp = tx_state_q == STATE_IDLE;

  // Output the data bits or IDLE/START.
  always_comb begin
    case (tx_state_q)
      STATE_IDLE:   o_uart_tx = '1;
      STATE_START:  o_uart_tx = '0;
      default:      o_uart_tx = tx_data_q[0];
    endcase
  end

  // Wait in RX IDLE until we see START, then shift in all the data.
  always_comb begin
    case (rx_state_q)
      STATE_IDLE:     rx_state_d = i_uart_rx ? STATE_IDLE : STATE_DATA_0;
      STATE_DATA_0:   rx_state_d = STATE_DATA_1;
      STATE_DATA_1:   rx_state_d = STATE_DATA_2;
      STATE_DATA_2:   rx_state_d = STATE_DATA_3;
      STATE_DATA_3:   rx_state_d = STATE_DATA_4;
      STATE_DATA_4:   rx_state_d = STATE_DATA_5;
      STATE_DATA_5:   rx_state_d = STATE_DATA_6;
      STATE_DATA_6:   rx_state_d = STATE_DATA_7;
      STATE_DATA_7:   rx_state_d = STATE_RX_OUT_0;
      STATE_RX_OUT_0: rx_state_d = rx_acp ? STATE_RX_OUT_1 : rx_state_q;
      default:      rx_state_d = STATE_IDLE;
    endcase
  end

  // Shift incoming RX data and shift out when accept is high.
  always_ff @(posedge i_uart_gck) begin
    case (rx_state_q)
      STATE_DATA_0,
      STATE_DATA_1,
      STATE_DATA_2,
      STATE_DATA_3,
      STATE_DATA_4,
      STATE_DATA_5,
      STATE_DATA_6,
      STATE_DATA_7:   rx_data_q      <= {i_uart_rx, rx_data_q[7:1]};
      STATE_RX_OUT_0: rx_data_q[3:0] <= rx_acp ? rx_data_q[7:4]
                                               : rx_data_q[3:0];
      default:        rx_data_q      <= rx_data_q;
    endcase
  end

  // Output is valid when we have a full RX buffer. We don't set high on the
  // second cycle as we need to be low for the clock gating.
  always_comb begin
    case (rx_state_q)
      STATE_RX_OUT_0: o_uart_rx_vld = '1;
      default:        o_uart_rx_vld = '0;
    endcase
  end

  // Output received data to the rest of the core.
  always_comb o_uart_rx = sqi_data_t'(rx_data_q[3:0]);

  // If this is the first cycle that EX is accepting RX data then we need to
  // hold the value for an extra cycle before shifting, but if we're part way
  // through already then we can shift immediately.
  always_comb rx_acp = i_uart_rx_acp && !i_uart_ex_op_acp;

endmodule
