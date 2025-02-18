`include "idli_pkg.svh"


// Contains the PC and incrementing logic.
module idli_pc_m import idli_pkg::*; (
  // Clock and reset.
  input  var logic  i_pc_gck,
  input  var logic  i_pc_rst_n,

  // Update control signals.
  input  var logic      i_pc_inc,
  input  var logic      i_pc_redirect,
  input  var sqi_data_t i_pc_redirect_data,

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
    end else if (i_pc_inc || i_pc_redirect) begin
      ctr_q <= ctr_q + 2'd1;
    end
  end

  // Compute the next sequential PC and carry out, making sure to reset back
  // to one if it's the final cycle or keep it high if we aren't currently
  // incrementing.
  always_comb begin
    {carry_d, o_pc_next} = o_pc + sqi_data_t'(carry_q);

    if (&ctr_q || !i_pc_inc) begin
      carry_d = '1;
    end
  end

  // Select the next PC based on the current control signals. Highest priority
  // is a redirect, in which case we take the incoming data. Next we increment
  // if requested, otherwise we hold the original value.
  always_comb begin
    casez ({i_pc_redirect, i_pc_inc})
      2'b1?:   pc_d = i_pc_redirect_data;
      2'b01:   pc_d = o_pc_next;
      default: pc_d = o_pc;
    endcase
  end

  // Output the current slice of the PC.
  always_comb o_pc = sqi_data_t'(pc_q[3:0]);

endmodule
