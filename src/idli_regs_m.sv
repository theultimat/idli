`include "idli_pkg.svh"


// General purpose register file containing 8x16b registers. These rotate and
// present a single 4b slice on each cycle.
module idli_regs_m import idli_pkg::*; (
  // Clock - no reset required.
  input  var logic  i_reg_gck,

  // Two read ports provided, B and C.
  input  var greg_t     i_reg_b,
  output var sqi_data_t o_reg_b_data,
  input  var greg_t     i_reg_c,
  output var sqi_data_t o_reg_c_data
);

  // Actual register data.
  logic [15:0] regs_q [8];

  // Output data on each read port.
  always_comb begin
    o_reg_b_data = 'x;

    for (int unsigned REG = 0; REG < 8; REG++) begin
      if (i_reg_b == greg_t'(REG)) begin
        o_reg_b_data = regs_q[REG][3:0];
      end
    end
  end

  always_comb begin
    o_reg_c_data = 'x;

    for (int unsigned REG = 0; REG < 8; REG++) begin
      if (i_reg_c == greg_t'(REG)) begin
        o_reg_c_data = regs_q[REG][3:0];
      end
    end
  end

  // Rotate registers on each cycle.
  // TODO Handle incoming write data.
  for (genvar REG = 0; REG < 8; REG++) begin : num_regs_b
    always_ff @(posedge i_reg_gck) begin
      regs_q[REG] <= {regs_q[REG][3:0], regs_q[REG][15:4]};
    end
  end : num_regs_b

endmodule
