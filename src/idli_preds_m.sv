`include "idli_pkg.svh"


// Predicate register file.
module idli_preds_m import idli_pkg::*; (
  // Clock - don't need reset.
  input  var logic  i_pred_gck,

  // One read port to decide if instruction should be executed.
  input  var preg_t i_pred_rd,
  output var logic  o_pred_rd_data,

  // Single write port for comparisons etc.
  input  var preg_t i_pred_wr,
  input  var logic  i_pred_wr_en,
  input  var logic  i_pred_wr_data
);

  // Register data - we don't need P3 as this always returns true.
  logic regs_q [3];

  // Whether we need to bypass the write value.
  logic bypass;


  // Read value comes from the flop unless we're currently writing or it's P3.
  always_comb begin
    o_pred_rd_data = '1;

    if (bypass) begin
      o_pred_rd_data = i_pred_wr_data;
    end else begin
      for (int unsigned REG = 0; REG < 3; REG++) begin
        if (i_pred_rd == preg_t'(REG)) begin
          o_pred_rd_data = regs_q[REG];
        end
      end
    end
  end

  // Bypass if we're currently writing the register being read and it isn't
  // P3.
  always_comb bypass = i_pred_wr_en && i_pred_wr == i_pred_rd
                                    && i_pred_wr != PREG_PT;

  // Write register with new value on edge.
  for (genvar REG = 0; REG < 3; REG++) begin : num_regs_b
    logic reg_d;

    always_comb begin
      reg_d = regs_q[REG];

      if (i_pred_wr_en && i_pred_wr == preg_t'(REG)) begin
        reg_d = i_pred_wr_data;
      end
    end

    always_ff @(posedge i_pred_gck) begin
      regs_q[REG] <= reg_d;
    end
  end : num_regs_b

endmodule
