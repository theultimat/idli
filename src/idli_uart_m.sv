`include "idli_pkg.svh"


// UART TX and RX.
module idli_uart_m import idli_pkg::*; (
  // Clock and reset.
  input  var logic  i_uart_gck,
  input  var logic  i_uart_rst_n,

  // TX interface.
  input  var sqi_data_t i_uart_tx,
  input  var logic      i_uart_tx_vld,
  output var logic      o_uart_tx_acp,
  output var logic      o_uart_tx
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
    STATE_DATA_7
  } state_t;

  // Current and next state for transmission.
  state_t tx_state_q;
  state_t tx_state_d;

  // Shift register for TX data.
  logic [7:0] tx_data_q;


  // Flop the next states.
  always_ff @(posedge i_uart_gck, negedge i_uart_rst_n) begin
    if (!i_uart_rst_n) begin
      tx_state_q <= STATE_IDLE;
    end else begin
      tx_state_q <= tx_state_d;
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

endmodule
