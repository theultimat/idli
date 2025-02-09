`include "idli_pkg.svh"


// Data is writtin into this buffer in one order and read out in the opposite.
// The contents of the data will rotate 4b every cycle, so WIDTH is given in
// terms of number of sqi_data_t.
module idli_sqi_buf_m import idli_pkg::*; #(
  parameter int unsigned WIDTH = 4
) (
  // Clock - no need for reset.
  input  var logic  i_sqi_gck,

  // Data input and output and whether data is currently being written, with
  // the write enable being one cycle ahead of the data.
  input  var logic      i_sqi_wr_en,
  input  var sqi_data_t i_sqi_data,
  output var sqi_data_t o_sqi_data
);

  // Data stored in the buffer.
  logic [WIDTH*$bits(sqi_data_t)-1:0] data_q;


  // The contents of the register rotate on every cycle, with the direction
  // being controlled by whether or not the write enable is set. When writing,
  // new data is pushed into the top of the buffer.
  always_ff @(posedge i_sqi_gck) begin
    if (i_sqi_wr_en) begin
      data_q <= {i_sqi_data, data_q[15:4]};
    end else begin
      data_q <= {data_q[11:0], data_q[15:12]};
    end
  end

  // Output data is always the top slice of the buffer.
  always_comb o_sqi_data = sqi_data_t'(data_q[15:12]);

endmodule
