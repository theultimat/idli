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

// Decoded operation. Contains control signals for execution.
typedef struct packed {
  // Register identifiers.
  preg_t  p;
  preg_t  q;
  greg_t  a;
  greg_t  b;
  greg_t  c;

  // Whether to read C or take the next 16b as an immediate.
  logic imm;
} op_t;

endpackage

`endif // idli_pkg_svh
