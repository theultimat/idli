`include "idli_pkg.svh"


// Contains the PC and incrementing logic.
module idli_pc_m import idli_pkg::*; (
  // Clock and reset.
  input  var logic  i_pc_gck,
  input  var logic  i_pc_rst_n,

  // Update control signals.
  input  var logic  i_pc_inc,

  // Current slice of the PC for use in execute.
  output var sqi_data_t o_pc,
  output var sqi_data_t o_pc_next
);

  // Current and next PC.
  logic [15:0] pc_q;
  sqi_data_t   pc_d;

  // Carry for the adder.
  logic carry_q;
  logic carry_d;

  // Counter for determining how far into the update we are.
  logic [1:0] ctr_q;


  // Program counter always rotates 4b every cycle.
  always_ff @(posedge i_pc_gck, negedge i_pc_rst_n) begin
    if (!i_pc_rst_n) begin
      pc_q    <= '0;
      carry_q <= '1;
    end else begin
      pc_q    <= {pc_d, pc_q[15:4]};
      carry_q <= carry_d;
    end
  end

  // Counter updates every cycle during an increment.
  always_ff @(posedge i_pc_gck, negedge i_pc_rst_n) begin
    if (!i_pc_rst_n) begin
      ctr_q <= '0;
    end else if (i_pc_inc) begin
      ctr_q <= ctr_q + 2'd1;
    end
  end

  // Compute the new PC. Incrementing is as simple as adding one each cycle,
  // which can be done using the carry in only.
  always_comb begin
    pc_d    = sqi_data_t'(pc_q[3:0]);
    carry_d = '1;

    if (i_pc_inc) begin
      {carry_d, pc_d} = pc_d + sqi_data_t'(carry_q);
    end

    // If this is the final cycle then the carry should be forced back to one
    // for the next increment.
    if (&ctr_q) begin
      carry_d = '1;
    end
  end

  // Output the current slice of the PC.
  always_comb o_pc      = sqi_data_t'(pc_q[3:0]);
  always_comb o_pc_next = pc_d;

endmodule
