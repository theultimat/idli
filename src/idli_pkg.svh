`ifndef idli_pkg_svh
`define idli_pkg_svh

package idli_pkg;

// Number of attached SQI memories.
localparam int unsigned SQI_NUM = 2;

// One memory contains the low nibbles, the other contains the high nubbles.
typedef enum logic {
  SQI_MEM_LO,
  SQI_MEM_HI
} sqi_mem_t;

// 4b of data per cycle on each SQI memory interface.
typedef logic [3:0] sqi_data_t;

// General purpose register and predicate register identifiers.
typedef logic [2:0] greg_t;
typedef logic [1:0] preg_t;

// Identifier for the always true predicate register.
localparam preg_t PREG_PT = preg_t'(2'd3);

// Identifier for the link register.
localparam greg_t GREG_LR = greg_t'(3'd6);

// Supported ALU operations.
typedef enum logic [1:0] {
  ALU_OP_ADD,
  ALU_OP_AND,
  ALU_OP_OR,
  ALU_OP_XOR
} alu_op_t;

// Comparisons.
typedef enum logic [1:0] {
  CMP_OP_EQ,
  CMP_OP_NE,
  CMP_OP_LT,
  CMP_OP_GE
} cmp_op_t;

// Possible source locations for LHS operand.
typedef enum logic [1:0] {
  LHS_SRC_REG,
  LHS_SRC_ZERO,
  LHS_SRC_PC
} lhs_src_t;

// Possible source locations for RHS operand.
typedef enum logic [1:0] {
  RHS_SRC_REG,
  RHS_SRC_IMM,
  RHS_SRC_UART
} rhs_src_t;

// Decoded operation. Contains control signals for execution.
typedef struct packed {
  // Register identifiers.
  preg_t  p;
  preg_t  q;
  greg_t  a;
  greg_t  b;
  greg_t  c;

  // Whether operand values are valid, excluding P which is always valid.
  logic q_vld;
  logic a_vld;
  logic b_vld;
  logic c_vld;

  // Where to take source operands from.
  lhs_src_t lhs_src;
  rhs_src_t rhs_src;

  // ALU control signals.
  alu_op_t alu_op;
  logic    alu_cin;
  logic    alu_rhs_inv;

  // Whether PC or LR are written by the instruction.
  logic   wr_pc;
  logic   wr_lr;

  // UART control signals.
  logic uart_tx_lo;
  logic uart_tx_hi;
  logic uart_rx_lo;
  logic uart_rx_hi;

  // Comparison operator.
  cmp_op_t cmp_op;
  logic    cmp_signed;
} op_t;

endpackage

`endif // idli_pkg_svh
