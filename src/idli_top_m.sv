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
  output var sqi_data_t [SQI_NUM-1:0] o_top_sio,

  // UART interface.
  input  var logic i_top_uart_rx,
  output var logic o_top_uart_tx
);

  sqi_data_t sqi_rd_data;
  logic      sqi_rd_data_vld;

  op_t  dcd_op;
  logic dcd_op_vld;

  sqi_data_t pc;
  sqi_data_t pc_next;

  logic       ex_redirect;
  sqi_data_t  ex_alu_out;
  logic       ex_uart_tx_vld;
  logic       ex_op_acp;
  op_t        ex_op;
  logic       ex_op_vld;
  logic [1:0] ex_ctr;
  logic       ex_uart_rx_acp;

  logic       uart_tx_acp;
  logic       uart_rx_vld;
  sqi_data_t  uart_rx_data;

  logic       sync_gck;

  idli_sqi_m sqi_u (
    .i_sqi_gck        (sync_gck),
    .i_sqi_rst_n      (i_top_rst_n),

    .o_sqi_sck        (o_top_sck),
    .o_sqi_cs         (o_top_cs),

    .i_sqi_sio        (i_top_sio),
    .o_sqi_sio        (o_top_sio),

    .o_sqi_data       (sqi_rd_data),
    .o_sqi_data_vld   (sqi_rd_data_vld),

    .i_sqi_addr_en    (ex_redirect),
    .i_sqi_lifo_data  (ex_alu_out)
  );

  idli_decode_m decode_u (
    .i_dcd_gck          (sync_gck),
    .i_dcd_rst_n        (i_top_rst_n),

    .i_dcd_enc          (sqi_rd_data),
    .i_dcd_enc_vld      (sqi_rd_data_vld),

    .o_dcd_op           (dcd_op),
    .o_dcd_op_vld       (dcd_op_vld),

    .i_dcd_ex_redirect  (ex_redirect)
  );

  idli_ex_m ex_u (
    .i_ex_gck         (sync_gck),
    .i_ex_rst_n       (i_top_rst_n),

    .i_ex_op          (dcd_op),
    .i_ex_op_vld      (dcd_op_vld),
    .o_ex_op_acp      (ex_op_acp),

    .i_ex_imm         (sqi_rd_data),

    .i_ex_pc          (pc),
    .i_ex_pc_next     (pc_next),
    .o_ex_redirect    (ex_redirect),

    .o_ex_alu_out     (ex_alu_out),

    .o_ex_op          (ex_op),
    .o_ex_op_vld      (ex_op_vld),
    .o_ex_ctr         (ex_ctr),

    .i_ex_uart_rx     (uart_rx_data),
    .o_ex_uart_tx_vld (ex_uart_tx_vld),
    .o_ex_uart_rx_acp (ex_uart_rx_acp)
  );

  idli_pc_m pc_u (
    .i_pc_gck           (sync_gck),
    .i_pc_rst_n         (i_top_rst_n),

    .i_pc_inc           (sqi_rd_data_vld),
    .i_pc_redirect      (ex_redirect),
    .i_pc_redirect_data (ex_alu_out),

    .o_pc               (pc),
    .o_pc_next          (pc_next)
  );

  idli_uart_m uart_u (
    .i_uart_gck       (i_top_gck),
    .i_uart_rst_n     (i_top_rst_n),

    .i_uart_rx        (i_top_uart_rx),
    .o_uart_rx_vld    (uart_rx_vld),
    .i_uart_rx_acp    (ex_uart_rx_acp),
    .o_uart_rx        (uart_rx_data),

    .i_uart_tx        (ex_alu_out),
    .i_uart_tx_vld    (ex_uart_tx_vld),
    .o_uart_tx_acp    (uart_tx_acp),
    .o_uart_tx        (o_top_uart_tx),

    .i_uart_ex_op_acp (ex_op_acp)
  );

  idli_sync_m sync_u (
    .i_sync_gck         (i_top_gck),
    .i_sync_rst_n       (i_top_rst_n),

    .i_sync_ex_op       (ex_op),
    .i_sync_ex_op_vld   (ex_op_vld),
    .i_sync_ex_ctr      (ex_ctr),
    .i_sync_uart_tx_acp (uart_tx_acp),
    .i_sync_uart_rx_vld (uart_rx_vld),

    .o_sync_gck         (sync_gck)
  );

endmodule
