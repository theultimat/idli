`include "idli_pkg.svh"


// LIFO structure for reversing data being sent to the memory. Data is on the
// same cycle as control.
module idli_lifo_m import idli_pkg::*; #(
  parameter int unsigned DEPTH = 4,
  parameter bit          RESET = 0
) (
  // Clock and reset.
  input  var logic  i_lifo_gck,
  input  var logic  i_lifo_rst_n,

  // Data input and output and associated control signals.
  input  var logic      i_lifo_push,
  input  var logic      i_lifo_pop,
  input  var sqi_data_t i_lifo_data,
  output var sqi_data_t o_lifo_data,

  // Whether there's 8b worth of data only - this will be used for detecting
  // when sign extension is required.
  output var logic      o_lifo_is_byte
);

  // Internal data storage.
  sqi_data_t [DEPTH-1:0] data_q;

  // Pointer for reading/writing.
  localparam int unsigned PTR_W = $clog2(DEPTH);
  typedef logic [PTR_W-1:0] ptr_t;

  ptr_t ptr_q;
  ptr_t ptr_d;


  // Flop the new pointer value.
  always_ff @(posedge i_lifo_gck, negedge i_lifo_rst_n) begin
    if (!i_lifo_rst_n) begin
      ptr_q  <= '1;
    end else begin
      ptr_q <= ptr_d;
    end
  end

  // Difference to the pointer depends on the push and pop signals.
  always_comb begin
    case ({i_lifo_push, i_lifo_pop})
      2'b01:   ptr_d = ptr_q - ptr_t'(1);
      2'b10:   ptr_d = ptr_q + ptr_t'(1);
      default: ptr_d = ptr_q;
    endcase
  end

  // Read data is always whatever the pointer currently indicates.
  always_comb o_lifo_data = data_q[ptr_q];

  // Write data is written into what the pointer will be on the next cycle.
  // TODO Check timing implications of using ptr_d?
  always_ff @(posedge i_lifo_gck, negedge i_lifo_rst_n) begin
    if (!i_lifo_rst_n && RESET) begin
      data_q <= '0;
    end else if (i_lifo_push) begin
      data_q[ptr_d] <= i_lifo_data;
    end
  end

  // We have a byte of data if the pointer is at 1 - this doesn't account for
  // any changes that may take place on the current cycle.
  always_comb o_lifo_is_byte = ptr_q == ptr_t'('d1);

endmodule
