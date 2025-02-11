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

// Supported ALU operations.
typedef enum logic [1:0] {
  ALU_OP_ADD,
  ALU_OP_AND,
  ALU_OP_OR,
  ALU_OP_XOR
} alu_op_t;

// Possible source locations for operand B.
typedef enum logic [1:0] {
  B_SRC_REG,
  B_SRC_ZERO,
  B_SRC_PC
} b_src_t;

// Possible source locations for operand C.
typedef enum logic {
  C_SRC_REG,
  C_SRC_IMM
} c_src_t;

// Decoded operation. Contains control signals for execution.
typedef struct packed {
  // Register identifiers.
  preg_t  p;
  preg_t  q;
  greg_t  a;
  greg_t  b;
  greg_t  c;

  // Whether operand values are valid, excluding P which is always valid.
  logic a_vld;
  logic b_vld;
  logic c_vld;

  // Where to take source operands from.
  b_src_t b_src;
  c_src_t c_src;

  // ALU control signals.
  alu_op_t alu_op;
} op_t;

endpackage

`endif // idli_pkg_svh
