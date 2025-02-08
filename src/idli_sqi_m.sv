`include "idli_pkg.svh"


// Communicates with the pair of connected SQI memories. One memory contains
// the high nibbles of each byte, while the other contains the low nibbles.
// The high memory is called MEM0 and the low MEM1.
module idli_sqi_m import idli_pkg::*; (
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
  output var sqi_data_t [SQI_NUM-1:0] o_sqi_sio
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
    STATE_DUMMY_1
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
      default:        state_d = state_q; // TODO
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

endmodule
