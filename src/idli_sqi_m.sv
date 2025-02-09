`include "idli_pkg.svh"


// Communicates with the pair of connected SQI memories. One memory contains
// the high nibbles of each byte, while the other contains the low nibbles.
// The high memory is called MEM0 and the low MEM1.
module idli_sqi_m import idli_pkg::*; #(
  localparam int unsigned SQI_BUF_NUM = 2
) (
  // Clock and reset.
  input  var logic  i_sqi_gck,
  input  var logic  i_sqi_rst_n,

  // SQI control signals. The second memory is half a clock cycle behind the
  // first, so the core, which is running at twice the clock rate, can receive
  // four bits of data per cycle.
  output var logic  [SQI_NUM-1:0] o_sqi_sck,
  output var logic  [SQI_NUM-1:0] o_sqi_cs,

  // SQI data ins and outs, one for each attached memory.
  input  var sqi_data_t [SQI_NUM-1:0] i_sqi_sio,
  output var sqi_data_t [SQI_NUM-1:0] o_sqi_sio,

  // Interface to the rest of the core, presented 4b per cycle.
  output var sqi_data_t   o_sqi_data,
  output var logic        o_sqi_data_vld
);

  // Internal states for the controller. Read and write operations can
  // generally be performed as follows:
  //
  // 1. Push CS high to reset.
  // 2. Pull CS low to select.
  // 3. Transmit the READ or WRITE instruction.
  // 4. Transmit the address to start the transaction.
  // 5. If READ, wait for the dummy byte to clock out.
  // 6. READ or WRITE bytes, high nibble first.
  //
  // In this configuration, we have two memories connected with one holding
  // the low nibbles of each byte and one holding the high. By keeping the two
  // SCK out of phase, such that the high trails the low, we can have
  // a continuous delivery of 4b per GCK cycle. As the memories are limited to
  // 20MHz, this means we can clock the core at 40MHz and still receive 4b per
  // cycle.
  typedef enum logic [3:0] {
    // Does nothing except pull CS to 1.
    STATE_RESET,

    // Transmit the instruction 4b per cycle.
    STATE_INSTR_0,
    STATE_INSTR_1,

    // Transmit the address 4b per cycle.
    STATE_ADDR_0,
    STATE_ADDR_1,
    STATE_ADDR_2,
    STATE_ADDR_3,

    // For reads, wait for the dummy byte to clock out.
    STATE_DUMMY_0,
    STATE_DUMMY_1,

    // Data is processed in 16b chunks, at 4b per GCK, so 8b per SCK.
    STATE_DATA_0,
    STATE_DATA_1
  } state_t;

  // READ and WRITE instructions as defined by the memory datasheet.
  typedef enum logic [7:0] {
    INSTR_READ  = 8'h3,
    INSTR_WRITE = 8'h2
  } instr_t;

  // Current and next state of the state machine for SQI0.
  state_t state_q;
  state_t state_d;

  // Internal counter for calculating SCK as each SCK is two GCK.
  logic ctr_q;

  // These signals control which of the buffers to write incoming data into,
  // and which of the two memories the data is coming from on each cycle.
  logic wr_mem_dst_q;
  logic wr_mem_src_q;

  // Output data from each of the buffers.
  sqi_data_t [SQI_BUF_NUM-1:0] buf_data_q;

  // We have two data buffers for accessing the memories. This enables for
  // pipelining, so we can write to one while reading from the other.
  for (genvar BUF = 0; BUF < SQI_BUF_NUM; BUF++) begin : num_buf_b
    idli_sqi_buf_m buf_u (
      .i_sqi_gck  (i_sqi_gck),

      .i_sqi_wr_en  (wr_mem_dst_q == BUF),
      .i_sqi_data   (i_sqi_sio[wr_mem_src_q]),
      .o_sqi_data   (buf_data_q[BUF])
    );
  end : num_buf_b

  // Calculate and save the next state. Each state only needs to be updated
  // every two GCK as SCK is is half the frequency.
  always_comb begin
    case (state_q)
      STATE_RESET:    state_d = STATE_INSTR_0;
      STATE_INSTR_0:  state_d = STATE_INSTR_1;
      STATE_INSTR_1:  state_d = STATE_ADDR_0;
      STATE_ADDR_0:   state_d = STATE_ADDR_1;
      STATE_ADDR_1:   state_d = STATE_ADDR_2;
      STATE_ADDR_2:   state_d = STATE_ADDR_3;
      STATE_ADDR_3:   state_d = STATE_DUMMY_0;  // TODO Assumes READ.
      STATE_DUMMY_0:  state_d = STATE_DUMMY_1;
      STATE_DUMMY_1:  state_d = STATE_DATA_0;
      STATE_DATA_0:   state_d = STATE_DATA_1;
      STATE_DATA_1:   state_d = STATE_DATA_0;   // TODO Assumes no new transaction.
      default:        state_d = state_q;        // TODO Should be unreachable.
    endcase
  end

  always_ff @(posedge i_sqi_gck, negedge i_sqi_rst_n) begin
    if (!i_sqi_rst_n) begin
      state_q <= STATE_RESET;
    end else if (ctr_q) begin
      state_q <= state_d;
    end
  end

  // The internal counter just toggles between zero and one to track which GCK
  // of the SCK we're currently in.
  always_ff @(posedge i_sqi_gck, negedge i_sqi_rst_n) begin
    if (!i_sqi_rst_n) begin
      ctr_q <= '0;
    end else begin
      ctr_q <= ~ctr_q;
    end
  end

  // Output SCK from the flop to avoid glitches.
  // TODO Just output the counter for now.
  always_comb o_sqi_sck[0] = ctr_q;

  // CS is always low except for the first cycle of a transaction.
  always_comb o_sqi_cs[0] = state_q == STATE_RESET;

  // The state machine is running half an SCK ahead of the data, so we can
  // output the data based on the flopped state.
  always_comb begin
    case (state_q)
      STATE_INSTR_0:  o_sqi_sio[0] = INSTR_READ[7:4]; // TODO Forced to READ
      STATE_INSTR_1:  o_sqi_sio[0] = INSTR_READ[3:0];
      STATE_ADDR_0:   o_sqi_sio[0] = '0;              // TODO Forced to 0
      STATE_ADDR_1:   o_sqi_sio[0] = '0;
      STATE_ADDR_2:   o_sqi_sio[0] = '0;
      STATE_ADDR_3:   o_sqi_sio[0] = '0;
      default:        o_sqi_sio[0] = 'x;
    endcase
  end

  // The buffer we're writing to swaps every 16b so we can pipeline accesses.
  always_ff @(posedge i_sqi_gck) begin
    if (ctr_q) begin
      // When starting a transaction reset back to the first buffer, otherwise
      // swap every time we end a transaction.

      // verilator lint_off CASEINCOMPLETE
      case (state_q)
        STATE_DUMMY_1: wr_mem_dst_q <= '0;
        STATE_DATA_1:  wr_mem_dst_q <= ~wr_mem_dst_q;
      endcase
      // verilator lint_on CASEINCOMPLETE
    end
  end

  // We memory we're reading from resets at the start of a 16b transaction and
  // otherwise swaps on every cycle.
  always_ff @(posedge i_sqi_gck) begin
    if (ctr_q && state_q == STATE_DUMMY_1) begin
      wr_mem_src_q <= '0;
    end else begin
      wr_mem_src_q <= ~wr_mem_src_q;
    end
  end

  // Each SQI memory is the delayed form of the one before it. In this core we
  // only have two memories.
  for (genvar SQI = 1; SQI < SQI_NUM; SQI++) begin : num_sqi_b
    // Some sims don't support one array element being assigned by a clocked
    // process and another being combinatorial so we flop into local variables
    // then comb those out.
    logic       local_sck_q;
    logic       local_cs_q;
    sqi_data_t  local_sio_q;

    always_ff @(posedge i_sqi_gck) begin
      local_sck_q <= o_sqi_sck[SQI - 1];
      local_cs_q  <= o_sqi_cs [SQI - 1];
      local_sio_q <= o_sqi_sio[SQI - 1];
    end

    always_comb o_sqi_sck[SQI] = local_sck_q;
    always_comb o_sqi_cs [SQI] = local_cs_q;
    always_comb o_sqi_sio[SQI] = local_sio_q;
  end : num_sqi_b

  // Data output to the rest of the core is taken from the buffer that isn't
  // currently being written to.
  always_comb o_sqi_data = wr_mem_dst_q ? buf_data_q[0] : buf_data_q[1];

  // We read data in from the memory in big endian, then need to cycle it back
  // out in little endian for the core. As a result, the read data is only
  // valid after we've completely finished reading the first 16b of data.
  always_ff @(posedge i_sqi_gck, negedge i_sqi_rst_n) begin
    if (!i_sqi_rst_n) begin
      o_sqi_data_vld <= '0;
    end else if (ctr_q) begin
      // verilator lint_off CASEINCOMPLETE
      case (state_q)
        STATE_RESET:  o_sqi_data_vld <= '0;
        STATE_DATA_1: o_sqi_data_vld <= '1; // TODO Flop invalid if going into reset.
      endcase
      // verilator lint_on CASEINCOMPLETE
    end
  end

endmodule
