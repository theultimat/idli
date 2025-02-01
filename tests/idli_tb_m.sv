`include "idli_pkg.svh"


// Instantiates the core and provides probes into the design for use by the
// external test script.
module idli_tb_m import idli_pkg::*; ();

  // Clock and reset driven by the test script.
  logic gck;
  logic rst_n;

  // SQI signals. Inputs are driven by the bench, outputs are presented.
  logic       sqi_sck;
  logic       sqi_cs;
  logic [7:0] sqi_sio_in;
  logic [7:0] sqi_sio_out;


  // Instantiate the top-level core.
  idli_top_m idli_u (
    .i_top_gck    (gck),
    .i_top_rst_n  (rst_n),

    .o_top_sck    (sqi_sck),
    .o_top_cs     (sqi_cs),
    .i_top_sio    (sqi_sio_in),
    .o_top_sio    (sqi_sio_out)
  );

endmodule
