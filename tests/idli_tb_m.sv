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

`ifdef idli_debug_signals_d

  // Internal debug signals.
  logic        ex_instr_done;
  logic [15:0] ex_gregs [8];
  logic        ex_pregs [4];

`endif // idli_debug_signals_d


  // Instantiate the top-level core.
  idli_top_m idli_u (
    .i_top_gck    (gck),
    .i_top_rst_n  (rst_n),

    .o_top_sck    ({sqi_sck_hi, sqi_sck_lo}),
    .o_top_cs     ({sqi_cs_hi, sqi_cs_lo}),
    .i_top_sio    ({sqi_sio_in_hi, sqi_sio_in_lo}),
    .o_top_sio    ({sqi_sio_out_hi, sqi_sio_out_lo})
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

`endif // idli_debug_signals_d

endmodule
