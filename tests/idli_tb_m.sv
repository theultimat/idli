`include "idli_pkg.svh"


// Instantiates the core and provides probes into the design for use by the
// external test script.
module idli_tb_m import idli_pkg::*; ();

  // Clock and reset driven by the test script.
  logic gck;
  logic rst_n;

  // SQI signals. Inputs are driven by the bench, outputs are presented.
  logic      sqi_sck_hi;
  logic      sqi_sck_lo;
  logic      sqi_cs_hi;
  logic      sqi_cs_lo;
  sqi_data_t sqi_sio_in_hi;
  sqi_data_t sqi_sio_in_lo;
  sqi_data_t sqi_sio_out_hi;
  sqi_data_t sqi_sio_out_lo;

  logic uart_tx;
  logic uart_rx;

`ifdef idli_debug_signals_d

  // Internal debug signals.
  logic        ex_instr_done;
  logic [15:0] ex_gregs [8];
  logic        ex_pregs [4];
  logic [15:0] ex_pc_q;
  logic [15:0] ex_pc_d;
  logic [15:0] ex_pc;
  logic        ex_gck;
  logic        ex_uart_rx;

`endif // idli_debug_signals_d


  // Instantiate the top-level core.
  idli_top_m idli_u (
    .i_top_gck      (gck),
    .i_top_rst_n    (rst_n),

    .o_top_sck      ({sqi_sck_hi, sqi_sck_lo}),
    .o_top_cs       ({sqi_cs_hi, sqi_cs_lo}),
    .i_top_sio      ({sqi_sio_in_hi, sqi_sio_in_lo}),
    .o_top_sio      ({sqi_sio_out_hi, sqi_sio_out_lo}),

    .i_top_uart_rx  (uart_rx),
    .o_top_uart_tx  (uart_tx)
  );


`ifdef idli_debug_signals_d

  // Probe signals within the core.
  always_comb ex_instr_done = idli_u.ex_u.instr_done;

  for (genvar REG = 0; REG < 8; REG++) begin : num_gregs_b
    // Take the value that will be flopped on the following cycle so it
    // matches the behavioural model on the edge the instruction completes.
    always_comb ex_gregs[REG] = idli_u.ex_u.regs_u.num_regs_b[REG].reg_d;
  end : num_gregs_b

  for (genvar REG = 0; REG < 3; REG++) begin : num_pregs_b
    always_comb ex_pregs[REG] = idli_u.ex_u.preds_u.num_regs_b[REG].reg_d;
  end : num_pregs_b

  // P3 is always true and doesn't exist in core so force it here.
  always_comb ex_pregs[3] = '1;

  // Rotate in the PC being fed into the execution units. To account for the
  // pipeline we subtract one from the PC when presenting it to the bench.
  always_comb ex_pc_d = {idli_u.ex_u.i_ex_pc, ex_pc_q[15:4]};
  always_comb ex_pc   = ex_pc_d - 16'd1;

  always_ff @(posedge ex_gck) begin
    ex_pc_q <= ex_pc_d;
  end

  // Take the gated clock out from the execution unit.
  always_comb ex_gck = idli_u.ex_u.i_ex_gck;

  // Signal indicates when UART RX is waiting for data.
  always_comb begin
    ex_uart_rx = '0;

    if (idli_u.ex_u.op_vld_q) begin
      ex_uart_rx = (idli_u.ex_u.op_q.uart_rx_lo && idli_u.ex_u.ctr_q == 2'd0)
                || (idli_u.ex_u.op_q.uart_rx_hi && idli_u.ex_u.ctr_q == 2'd2);
    end
  end

`endif // idli_debug_signals_d

endmodule
