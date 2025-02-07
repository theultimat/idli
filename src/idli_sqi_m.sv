`include "idli_pkg.svh"


// Communicates with the pair of connected SQI memories. One memory contains
// the high nibbles of each byte, while the other contains the low nibbles.
module idli_sqi_m import idli_pkg::*; (
  // Clock and reset.
  input  var logic  i_sqi_gck,
  input  var logic  i_sqi_rst_n,

  // SQI control signals. The second memory is half a clock cycle behind the
  // first, so the core, which is running at twice the clock rate, can receive
  // four bits of data per cycle.
  output var logic  [SQI_NUM-1:0] o_sqi_sck,
  output var logic  [SQI_NUM-1:0] o_sqi_cs,

  // SQI data ins and outs, one for each attached memory.
  input  var sqi_data_t [SQI_NUM-1:0] i_sqi_sio,
  output var sqi_data_t [SQI_NUM-1:0] o_sqi_sio
);

endmodule
