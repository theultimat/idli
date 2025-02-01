`include "idli_pkg.svh"


// Top-level module of the core.
module idli_top_m import idli_pkg::*; (
  // Clock and reset.
  input  var logic                    i_top_gck,
  input  var logic                    i_top_rst_n,

  // Memory interface.
  output var logic                    o_top_sck,
  output var logic                    o_top_cs,
  input  var sqi_data_t [SQI_NUM-1:0] i_top_sio,
  output var sqi_data_t [SQI_NUM-1:0] o_top_sio
);

  idli_sqi_m sqi_u (
    .i_sqi_gck    (i_top_gck),
    .i_sqi_rst_n  (i_top_rst_n),

    .o_sqi_sck    (o_top_sck),
    .o_sqi_cs     (o_top_cs),

    .i_sqi_sio    (i_top_sio),
    .o_sqi_sio    (o_top_sio)
  );

endmodule
