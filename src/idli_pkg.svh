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

endpackage

`endif // idli_pkg_svh
