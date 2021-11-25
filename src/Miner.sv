// === Miner.sv ===

module Miner
  #(parameter NONCE_BYTE_LEN = 24,
    parameter HASH_DELAY = 71)
  (
  // Clock & Reset
  input Clk,
  input Rst_n,
  // Inputs
  // Memory inputs
  input Update_I,
  input Clear_I,
  input [15:0] [31:0] Msg_I ,
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
  
  // The given nonce is valid
  output Vld_O,
  output [255:0] Hash_O,
  output [31:0] HashCounter_O,
  output [NONCE_BYTE_LEN*8-1:0] Nonce_O,
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
  logic [15:0] [31:0] nonce_msg;
  //pipeline counter
  logic [80:0] [6:0] pipeline;
  logic [6:0] ppln_cntr;
  
  // nonce
  logic [5:0] [31:0] nonce;
  logic [NONCE_BYTE_LEN*8-1:0] nonce_reg;
  logic [NONCE_BYTE_LEN*8-1:0] final_nonce;
 
  // hash output & result
  logic [7:0] [31:0] h_out;
  logic [2:0] [255:0] hash;
  logic vld_final_hash;
  
  //Calculation of hash is ready
  logic rdy_hash;
  
  logic [2:0] vld_hash;
  logic [1:0] next_block;
  
  // requesting the next word from the memory
  logic next_word;
  // updating the chunkhasher with new chunk
  logic new_chunk;
  logic dbl_chunk;
  
  // byte counter
  logic [10:0] byte_cntr;
  
  // flag to show if double hash started
  logic [2:0] dbl_hash;
  
  logic [10:0] byte_num;
  
  // validity of the 3 conditions
  logic [2:0] conditions;
  
  logic [7:0] group_index;
  //logic [7:0] chain_num;
  
  logic dbl_vld_hash;
  logic en_nonce_cnt;
  
  logic [31:0] hash_cntr_sum;
  logic [$clog2(HASH_DELAY)-1:0] hash_cntr;
  
  logic clr;

  assign clr = Clear_I || vld_final_hash;
  
  ChunkHasher #(
    .HASH_DELAY(HASH_DELAY)
    ) ChunkHasher_i(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .Clear_I(clr),
    .Update_I(new_chunk),
    .DblUpdate_I(dbl_chunk),
    .Msg_I(msg),
    .Byte_num_I(byte_num),
    .Next_O(next_block[0]),
    .H_O(h_out),
    .Vld_O(vld_hash[0]),
    .CNTR_O(hash_cntr)
  );
  
  assign en_nonce_cnt = (((state==FIRST_BLOCK) && (hash_cntr < HASH_DELAY)) || (state==DOUBLE_HASH && vld_hash[0]));
  
  always_ff@(posedge Clk or negedge Rst_n)
  begin : nonce_counter
    if(~Rst_n) begin
      nonce_reg <= 0;
    end
    else if(Update_I) begin
      nonce_reg <= Nonce_I;
    end
    else if(en_nonce_cnt)
      nonce_reg <= nonce_reg + 1;
  end
      
  always_ff@(posedge Clk or negedge Rst_n)
  begin : nonce_register
    if(~Rst_n) begin
      nonce <= 0;
    end
    else begin
      nonce[0] = nonce_reg[191:160];
      nonce[1] = nonce_reg[159:128];
      nonce[2] = nonce_reg[127:96];
      nonce[3] = nonce_reg[95:64];
      nonce[4] = nonce_reg[63:32];
      nonce[5] = nonce_reg[31:0];
    end
  end

  
  always_comb
  begin : nonce_message
    if(state==FIRST_BLOCK) begin
      msg[0] <= {<<8{nonce[0]}};
      msg[1] <= {<<8{nonce[1]}};
      msg[2] <= {<<8{nonce[2]}};
      msg[3] <= {<<8{nonce[3]}};
      msg[4] <= {<<8{nonce[4]}};
      msg[5] <= {<<8{nonce[5]}};
      msg[15:6] <= Msg_I[15:6];
    end
    else if(state==DOUBLE_HASH) begin
      msg[15:8] <= 0;
      msg[7:0] <= h_out[7:0];
    end 
    else
      msg <= Msg_I;
  end
  
  
////////////////////////// 
// Valid Shift Register //
//////////////////////////

  always_ff@(posedge Clk or negedge Rst_n)
  begin : valid_shr
    if(~Rst_n) begin
      vld_hash[2:1] <= 2'b00;
      dbl_hash[2:1] <= 2'b00;
      next_block[1] <= 1'b0;
      hash[1] <= 0;
    end
    else begin
      vld_hash[2:1] <= vld_hash[1:0];
      dbl_hash[2:1] <= dbl_hash[1:0];
      next_block[1] <= next_block[0];
      hash[1] <= hash[0];
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
        if(clr)
          next_state <= IDLE;
        else if(Update_I)
          next_state <= FIRST_BLOCK;
        else if(next_block[0] || ByteNum_I==0)
          next_state <= MIDDLE_BLOCKS;
      end//FIRST_BLOCK

      MIDDLE_BLOCKS: begin
        if(clr)
          next_state <= IDLE;
        else if(Update_I)
          next_state <= FIRST_BLOCK;
        // rising edge of the valid hash
        else if(vld_hash[1:0]==2'b01)
          next_state <= DOUBLE_HASH;
      end//MIDDLE_BLOCKS
      
      DOUBLE_HASH: begin
        if(clr)
          next_state <= IDLE;
        else if(Update_I || (vld_hash[1:0]==2'b01))
          next_state <= FIRST_BLOCK;  
      end//DOUBLE_HASH

      default:
          next_state <= state;
    endcase
  end
  
  //sequential FSM
  always_ff@(posedge Clk or negedge Rst_n)
  begin : fsm_seq
    if(~Rst_n) begin
      dbl_hash[0] <= 1'b0;
    end  
    else begin
      case (state)
      
        IDLE: begin
          dbl_hash[0] <= 1'b0;
        end//IDLE
        
        FIRST_BLOCK: begin
          if(next_block[0])
            dbl_hash[0] <= 1'b0;

        end//FIRST_BLOCK

        MIDDLE_BLOCKS: begin
          // request from the chunk hasher        
        end// MIDDLE_BLOCKS
        
        DOUBLE_HASH: begin
          // double hash has started
          if(vld_hash[1:0]==2'b01)
            dbl_hash[0] <= 1'b1;
            
        end//DOUBLE_HASH
        
        default: begin
          dbl_hash[0] <= 1'b0;
        end// default
        
      endcase
    end
  end
  
  
  assign next_word = (next_block[0] && (!vld_hash[0]) && byte_cntr < ByteNum_I);
  assign Next_O = next_block[0] && (!vld_hash[0]);
  
  always_ff@(posedge Clk or negedge Rst_n)
  begin : new_chunk_reg
    if(~Rst_n) 
      dbl_chunk <= 0;
    // start the new hashing
    else if(state==MIDDLE_BLOCKS && (vld_hash[1:0]==2'b01)) begin
      dbl_chunk <= 1'b1;
    end
    else
      dbl_chunk <= 1'b0;
  end
  
  assign new_chunk = Update_I;
  
////////////////////
// Byte Counter   //
////////////////////

  
  always_ff@(posedge Clk or negedge Rst_n)
  begin : byte_counter
    if(~Rst_n)
      byte_cntr <= 0;
    else if((vld_hash[1:0]==2'b01) || Update_I)
      byte_cntr <= 0;
    else if(next_word)
      byte_cntr <= byte_cntr + 512;
  end
  
  always_ff@(posedge Clk or negedge Rst_n)
  begin : byte_num_reg
    if(~Rst_n)
      byte_num <= 0;
    else if(Update_I || (dbl_vld_hash && vld_hash[0]))
      byte_num <= ByteNum_I;
    else if((state==MIDDLE_BLOCKS) && (vld_hash[1:0]==2'b01))
      byte_num <= 32;
  end
  
//////////////////
// Hash Counter //
//////////////////

  always_ff@(posedge Clk or negedge Rst_n)
  begin : hash_counter
    if(~Rst_n)
      hash_cntr_sum <= 0;
    else if(Update_I)
      hash_cntr_sum <= 0;
    else if(dbl_hash[1] && !vld_final_hash)
      hash_cntr_sum <= hash_cntr_sum + 1;
  end
  
  assign HashCounter_O = hash_cntr_sum;
  
////////////////////
// Handling hash  //
////////////////////

  always_ff@(posedge Clk or negedge Rst_n)
  begin : valid_hash
    if(~Rst_n)
      hash[0]  <= '1;
    else if(dbl_hash[0]) begin
      hash[0][255:224] = {<<8{h_out[0]}};
      hash[0][223:192] = {<<8{h_out[1]}};
      hash[0][191:160] = {<<8{h_out[2]}};
      hash[0][159:128] = {<<8{h_out[3]}};
      hash[0][127:96] = {<<8{h_out[4]}};
      hash[0][95:64] = {<<8{h_out[5]}};
      hash[0][63:32] = {<<8{h_out[6]}};
      hash[0][31:0] = {<<8{h_out[7]}};
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
    else if(dbl_hash[1]) begin
      //chain_num <= ChainNum_I;
      //group_index <= hash[15:0]%chain_num;
      //bitwise AND with minus 1 -> modulus on the power of two
      group_index <= hash[0][15:0] & (ChainNum_I-1);
    end
  end
  
  //assign group_index = hash[15:0]%ChainNum_I;
  
  assign conditions[0] = (hash[1] <= Target_I);
  assign conditions[1] = ((group_index>>GroupsShifter_I)==FromGroup_I);
  //assign conditions[2] = ((group_index%Groups_I)==ToGroup_I);
  //bitwise AND with minus 1 -> modulus on the power of two
  assign conditions[2] = ((group_index & (Groups_I-1))==ToGroup_I);

  always_ff@(posedge Clk or negedge Rst_n)
  begin : check_hash
    if(~Rst_n) begin
      vld_final_hash  <= 0;
      rdy_hash <= 0;
      hash[2] <= 0;
      final_nonce <= 0;
    end
    else if(Update_I) begin
      vld_final_hash <= 0;
      rdy_hash <= 0;
      hash[2] <= 0;
      final_nonce <= 0;
    end
    // checking the conditions
    else if(dbl_hash[2]) begin
      if(&conditions) begin
        vld_final_hash <= 1'b1;
        hash[2] <= hash[1];
        final_nonce <= nonce_reg - (HASH_DELAY+4);
      end
      rdy_hash <= 1'b1;
    end
  end
  
  assign Hash_O = hash[2];
  assign Rdy_O = dbl_vld_hash & vld_hash[0];
  assign Nonce_O = final_nonce;
  assign Vld_O = vld_final_hash;
  
  
  always_ff@(posedge Clk or negedge Rst_n)
  begin : double_valid_hash
    if(~Rst_n) begin
      dbl_vld_hash <= 0;
    end
    else if(vld_hash[0]) begin
      dbl_vld_hash <= ~dbl_vld_hash;
    end
  end
  
  //ILA
  //assign Cond_O = conditions;
  
endmodule : Miner