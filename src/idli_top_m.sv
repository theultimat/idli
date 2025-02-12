`include "idli_pkg.svh"


// Top-level module of the core.
module idli_top_m import idli_pkg::*; (
  // Clock and reset.
  input  var logic                    i_top_gck,
  input  var logic                    i_top_rst_n,

  // Memory interface.
  output var logic      [SQI_NUM-1:0] o_top_sck,
  output var logic      [SQI_NUM-1:0] o_top_cs,
  input  var sqi_data_t [SQI_NUM-1:0] i_top_sio,
  output var sqi_data_t [SQI_NUM-1:0] o_top_sio
);

  sqi_data_t sqi_rd_data;
  logic      sqi_rd_data_vld;

  op_t  dcd_op;
  logic dcd_op_vld;

  idli_sqi_m sqi_u (
    .i_sqi_gck      (i_top_gck),
    .i_sqi_rst_n    (i_top_rst_n),

    .o_sqi_sck      (o_top_sck),
    .o_sqi_cs       (o_top_cs),

    .i_sqi_sio      (i_top_sio),
    .o_sqi_sio      (o_top_sio),

    .o_sqi_data     (sqi_rd_data),
    .o_sqi_data_vld (sqi_rd_data_vld)
  );

  idli_decode_m decode_u (
    .i_dcd_gck      (i_top_gck),
    .i_dcd_rst_n    (i_top_rst_n),

    .i_dcd_enc      (sqi_rd_data),
    .i_dcd_enc_vld  (sqi_rd_data_vld),

    .o_dcd_op       (dcd_op),
    .o_dcd_op_vld   (dcd_op_vld)
  );

  idli_ex_m ex_u (
    .i_ex_gck     (i_top_gck),
    .i_ex_rst_n   (i_top_rst_n),

    .i_ex_op      (dcd_op),
    .i_ex_op_vld  (dcd_op_vld),
    // verilator lint_off PINCONNECTEMPTY
    .o_ex_op_acp  (),
    // verilator lint_on PINCONNECTEMPTY

    .i_ex_imm     (sqi_rd_data)
  );

endmodule
