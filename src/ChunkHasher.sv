// === ChunkHasher.sv ===

`include "defines.sv"

module ChunkHasher
  (
  // Clock & Reset
  input Clk,
  input Rst_n,
  // Inputs
  // FIFO inputs
  input Vld_I,
  input [7:0] [31:0] Msg_I,
  // Number of Bytes in the chunk
  // Max 1024
  input [10:0] Byte_num_I,
  
  // Outputs
  //FIFO outputs
  output Rd_O,
  
  //final result
  output [7:0] [31:0] H_O,
  output Done_O
 
  );
  
  typedef enum {IDLE, FIRST_BLOCK, MIDDLE_BLOCKS, LAST_BLOCK} state_t;
  
  state_t next_state;
  state_t state;
  
  bit chunk_start;
  bit chunk_end;
  bit root;
  
  HashGen HashGen_i(
    .Clk(Clk),
    .Strt_I(),
    .BL_I(),
    .CS_flg_I(),
    .CE_flg_I(),
    .ROOT_flg_I(),
    .H_I(),
    .Msg0_I(),
    .Msg1_I(),
    .Msg2_I(),
    .Msg3_I(),
    .Msg4_I(),
    .Msg5_I(),
    .Msg6_I(),
    .Msg7_I(),
    .Msg8_I(),
    .Msg9_I(),
    .Msg10_I(),
    .Msg11_I(),
    .Msg12_I(),
    .Msg13_I(),
    .Msg14_I(),
    .Msg15_I(),
    .Vld_O(),
    .H0_O(),
    .H1_O(),
    .H2_O(),
    .H3_O(),
    .H4_O(),
    .H5_O(),
    .H6_O(),
    .H7_O() 
  );
  
  
/////////
// FSM //
/////////
// seq logic
  always_ff@(posedge Clk or negedge Rst_n)
  begin : fsm_seq
    if(~Rst_n)
      state <= IDLE;
    else
      state <= next_state;
  end
  
// next state decoder
  always_comb() 
  begin : next_state_decode
    next_state <= state;
    case (state)     
      IDLE:
      
      FIRST_BLOCK:

      MIDDLE_BLOCKS:

      LAST_BLOCK:

      default:
          next_state <= state;
    endcase
  end
  
  
endmodule