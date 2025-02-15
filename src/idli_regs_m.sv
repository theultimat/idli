`include "idli_pkg.svh"


// General purpose register file containing 8x16b registers. These rotate and
// present a single 4b slice on each cycle.
module idli_regs_m import idli_pkg::*; (
  // Clock - no reset required.
  input  var logic  i_reg_gck,

  // Two read ports provided, LHS and RHS.
  input  var greg_t     i_reg_lhs,
  output var sqi_data_t o_reg_lhs_data,
  input  var greg_t     i_reg_rhs,
  output var sqi_data_t o_reg_rhs_data,

  // Single write port.
  input  var greg_t     i_reg_wr,
  input  var logic      i_reg_wr_en,
  input  var sqi_data_t i_reg_wr_data
);

  // Actual register data.
  logic [15:0] regs_q [8];

  // Output data on each read port.
  always_comb begin
    o_reg_lhs_data = 'x;

    for (int unsigned REG = 0; REG < 8; REG++) begin
      if (i_reg_lhs == greg_t'(REG)) begin
        o_reg_lhs_data = regs_q[REG][3:0];
      end
    end
  end

  always_comb begin
    o_reg_rhs_data = 'x;

    for (int unsigned REG = 0; REG < 8; REG++) begin
      if (i_reg_rhs == greg_t'(REG)) begin
        o_reg_rhs_data = regs_q[REG][3:0];
      end
    end
  end

  // Rotate registers on each cycle.
  // TODO Handle incoming write data.
  for (genvar REG = 0; REG < 8; REG++) begin : num_regs_b
    sqi_data_t reg_d;

    // Data to rotate in is the old value or the incoming data if we're
    // currently writing to this register.
    always_comb begin
      reg_d = sqi_data_t'(regs_q[REG][3:0]);

      if (i_reg_wr_en && i_reg_wr == greg_t'(REG)) begin
        reg_d = i_reg_wr_data;
      end
    end

    always_ff @(posedge i_reg_gck) begin
      regs_q[REG] <= {reg_d, regs_q[REG][15:4]};
    end
  end : num_regs_b

endmodule
