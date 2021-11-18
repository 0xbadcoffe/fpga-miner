// === Miner.sv ===

module Miner
  #(parameter NONCE_BYTE_LEN = 24)
  (
  // Clock & Reset
  input Clk,
  input Rst_n,
  // Inputs
  // Memory inputs
  input Update_I,
  input Clear_I,
  input [31:0] Msg_I,
  // Number of Bytes in the chunk
  // Nonce + headerBlob <= 1024 bytes
  // headerBlob <= 1000 bytes
  input [10:0] ByteNum_I,
  
  input [7:0] FromGroup_I,
  input [7:0] ToGroup_I,
  input [NONCE_BYTE_LEN*8-1:0] Nonce_I,
  input [255:0] Target_I,
  
  input [7:0] Groups_I, //4
  input [7:0] ChainNum_I, //16 Grroups*Groups
  input [7:0] GroupsShifter_I,//2
  
  // Outputs
  //FIFO outputs
  output Next_O,
  
  
  // The give nonce is valid
  output Vld_O,
  output [255:0] Hash_O,
  // Calculation is ready
  output Rdy_O
  
  //ILA
  //output [2:0] Cond_O
 
  );
  
  
  // states for the FSM
  typedef enum {IDLE, FIRST_BLOCK, MIDDLE_BLOCKS, DOUBLE_HASH} state_t;
  
  state_t next_state;
  state_t state;
 
  // message inputs
  logic [15:0] [31:0] msg;
  logic [15:0] [31:0] msg_next;
  
  shortint msg_cntr;
  
  // nonce
  logic [5:0] [31:0] nonce;
 
  // hash output & result
  logic [7:0] [31:0] h_out;
  logic [255:0] hash;
  logic vld_final_hash;
  
  //Calculation of hash is ready
  logic rdy_hash;
  
  logic [2:0] vld_hash;
  logic next_block;
  
  // requesting the next word from the memory
  logic next_word_reg;
  logic next_word;
  // updating the chunkhasher with new chunk
  logic new_chunk;
  
  // byte counter
  logic [10:0] byte_cntr;
  
  // flag to show if double hash started
  logic [1:0] dbl_hash;
  
  logic [10:0] byte_num;
  
  // validity of the 3 conditions
  logic [2:0] conditions;
  
  logic [7:0] group_index;
  //logic [7:0] chain_num;

  
  ChunkHasher ChunkHasher_i(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .Update_I(new_chunk),
    .Msg_I(msg),
    .Byte_num_I(byte_num),
    .Next_O(next_block),
    .H_O(h_out),
    .Vld_O(vld_hash[0])
  );
  
  assign nonce[0] = Nonce_I[191:160];
  assign nonce[1] = Nonce_I[159:128];
  assign nonce[2] = Nonce_I[127:96];
  assign nonce[3] = Nonce_I[95:64];
  assign nonce[4] = Nonce_I[63:32];
  assign nonce[5] = Nonce_I[31:0];
  
////////////////////////// 
// Valid Shift Register //
//////////////////////////

  always_ff@(posedge Clk or negedge Rst_n)
  begin : valid_shr
    if(~Rst_n) begin
      vld_hash[2:1] <= 2'b00;
      dbl_hash[1] <= 1'b0;
    end
    else begin
      vld_hash[2:1] <= vld_hash[1:0];
      dbl_hash[1] <= dbl_hash[0];
    end
  end
  
/////////
// FSM //
/////////

  // seq logic
  always_ff@(posedge Clk or negedge Rst_n)
  begin : state_sync
    if(~Rst_n)
      state <= IDLE;
    else
      state <= next_state;
  end
  
  // next state decoder
  always_comb
  begin : next_state_decode
    next_state <= state;
    case (state)
    
      IDLE: begin
        if(Update_I)
          next_state <= FIRST_BLOCK;
      end//IDLE
      
      FIRST_BLOCK: begin
        if(Clear_I)
          next_state <= IDLE;
        else if(Update_I)
          next_state <= FIRST_BLOCK;
        else if(msg_cntr==9 || ByteNum_I==0)
          next_state <= MIDDLE_BLOCKS;
      end//FIRST_BLOCK

      MIDDLE_BLOCKS: begin
        if(Clear_I)
          next_state <= IDLE;
        else if(Update_I)
          next_state <= FIRST_BLOCK;
        // rising edge of the valid hash
        else if(vld_hash[1:0]==2'b01)
          next_state <= DOUBLE_HASH;
      end//MIDDLE_BLOCKS
      
      DOUBLE_HASH: begin
        if(Clear_I)
          next_state <= IDLE;
        else if(Update_I)
          next_state <= FIRST_BLOCK;
        // rising edge of the valid hash
        else if(vld_hash[1:0]==2'b01)
          next_state <= IDLE;   
      end//DOUBLE_HASH

      default:
          next_state <= state;
    endcase
  end
  
  //sequential FSM
  always_ff@(posedge Clk or negedge Rst_n)
  begin : fsm_seq
    if(~Rst_n) begin
      msg <= 0;
      msg_next <= 0;
      msg_cntr <= 0;
      next_word_reg <= 0;
      new_chunk <= 1'b0;
      dbl_hash[0] <= 1'b0;
      byte_num <= 0;
    end  
    else begin
      case (state)
      
        IDLE: begin
          msg <= 0;
          msg_next <= 0;
          msg_cntr <= 0;
          next_word_reg <= 0;
          new_chunk <= 1'b0;
          dbl_hash[0] <= 1'b0;
          byte_num <= 0;
        end//IDLE
        
        FIRST_BLOCK: begin
          dbl_hash[0] <= 1'b0;
          byte_num <= ByteNum_I;
          // first part of the message coming from the nonce
          msg[0] <= {<<8{nonce[0]}};
          msg[1] <= {<<8{nonce[1]}};
          msg[2] <= {<<8{nonce[2]}};
          msg[3] <= {<<8{nonce[3]}};
          msg[4] <= {<<8{nonce[4]}};
          msg[5] <= {<<8{nonce[5]}};
          msg[msg_cntr+6] <= Msg_I;
          // filling up the message fields with serial data
          if(msg_cntr<9 && byte_cntr < ByteNum_I) begin
            next_word_reg <= 1'b1;
            new_chunk <= 1'b0;
            if(next_word)
              msg_cntr <= msg_cntr + 1;
          end
          else begin
            msg_cntr <= 0;
            next_word_reg <= 1'b0;
            new_chunk <= 1'b1;
            if(ByteNum_I==0)
              msg <= 0;
          end
        end//FIRST_BLOCK

        MIDDLE_BLOCKS: begin
          new_chunk <= 1'b0;
          // request from the chunk hasher
          if(next_block) begin
            msg <= msg_next;
            msg_next <= 0;
            msg_cntr <= 0;
          end
          // filling up the message fields with the incoming data
          if(next_word)
            msg_next[msg_cntr] <= Msg_I;
          // filling up the message fields with serial data
          if(msg_cntr<15 && byte_cntr < ByteNum_I) begin
            next_word_reg <= 1'b1;
            if(next_word)
              msg_cntr <= msg_cntr + 1;
          end
          else
            next_word_reg <= 1'b0;
          
        end// MIDDLE_BLOCKS
        
        DOUBLE_HASH: begin
          byte_num <= 32;
          msg[15:8] <= 0;
          msg[7:0] <= h_out[7:0];
          // start the new hashing
          if(~dbl_hash[0]) begin
            new_chunk <= 1'b1;
          end
          else
            new_chunk <= 1'b0;
          // double hash has started
          if(new_chunk)
            dbl_hash[0] <= 1'b1;
            
        end//DOUBLE_HASH
        
        default: begin
          msg <= 0;
          msg_next <= 0;
          msg_cntr <= 0;
          next_word_reg <= 0;
          new_chunk <= 1'b0;
          dbl_hash[0] <= 1'b0;
          byte_num <= 0;
        end// default
        
      endcase
    end
  end
  
  assign next_word = (next_word_reg && byte_cntr < ByteNum_I);
  assign Next_O = next_word;
  
////////////////////
// Byte Counter   //
////////////////////

  
  always_ff@(posedge Clk or negedge Rst_n)
  begin : byte_counter
    if(~Rst_n)
      byte_cntr <= NONCE_BYTE_LEN;
    else if((vld_hash[1:0]==2'b01) || Update_I)
      byte_cntr <= NONCE_BYTE_LEN;
    else if(next_word)
      byte_cntr <= byte_cntr + 4;
  end
  
  
  
////////////////////
// Handling hash  //
////////////////////

  always_ff@(posedge Clk or negedge Rst_n)
  begin : valid_hash
    if(~Rst_n)
      hash  <= '1;
    else if(vld_hash[0]) begin
      hash[255:224] = {<<8{h_out[0]}};
      hash[223:192] = {<<8{h_out[1]}};
      hash[191:160] = {<<8{h_out[2]}};
      hash[159:128] = {<<8{h_out[3]}};
      hash[127:96] = {<<8{h_out[4]}};
      hash[95:64] = {<<8{h_out[5]}};
      hash[63:32] = {<<8{h_out[6]}};
      hash[31:0] = {<<8{h_out[7]}};
    end
  end
  
//////////////////////////
// Checking double hash //
//////////////////////////

  always_ff@(posedge Clk or negedge Rst_n)
  begin : group_idx
    if(~Rst_n) begin
      group_index <= 0;
      //chain_num <= 0;
    end
    else begin
      //chain_num <= ChainNum_I;
      //group_index <= hash[15:0]%chain_num;
      //bitwise AND with minus 1 -> modulus on the power of two
      group_index <= hash[15:0] & (ChainNum_I-1);
    end
  end
  
  //assign group_index = hash[15:0]%ChainNum_I;
  
  assign conditions[0] = (hash <= Target_I);
  assign conditions[1] = ((group_index>>GroupsShifter_I)==FromGroup_I);
  //assign conditions[2] = ((group_index%Groups_I)==ToGroup_I);
  //bitwise AND with minus 1 -> modulus on the power of two
  assign conditions[2] = ((group_index & (Groups_I-1))==ToGroup_I);

  always_ff@(posedge Clk or negedge Rst_n)
  begin : check_hash
    if(~Rst_n) begin
      vld_final_hash  <= 0;
      rdy_hash <= 0;
    end
    else if(Update_I) begin
      vld_final_hash <= 0;
      rdy_hash <= 0;
    end
    // checking the conditions
    else if(vld_hash==3'b111 && dbl_hash[1]) begin
      vld_final_hash <= &conditions;
      rdy_hash <= 1'b1;
    end
  end
  
  assign Hash_O = hash;
  assign Rdy_O = rdy_hash;
  assign Vld_O = vld_final_hash;
  
  //ILA
  //assign Cond_O = conditions;
  
endmodule : Miner