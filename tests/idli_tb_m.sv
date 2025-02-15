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
  logic ex_instr_done;

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

`endif // idli_debug_signals_d

endmodule
