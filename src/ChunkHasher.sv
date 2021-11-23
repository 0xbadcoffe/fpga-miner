// === ChunkHasher.sv ===

`include "defines.sv"

module ChunkHasher
  #(parameter HASH_DELAY = 71)
  (
  // Clock & Reset
  input Clk,
  input Rst_n,
  input Clear_I,
  // Inputs
  // Memory inputs
  input Update_I,
  input DblUpdate_I,
  input [15:0] [31:0] Msg_I,
  // Number of Bytes in the chunk
  // Max 1024
  input [10:0] Byte_num_I,
  
  // Outputs
  //FIFO outputs
  output Next_O,
  
  //final result
  output [7:0] [31:0] H_O,
  output [$clog2(HASH_DELAY)-1:0] CNTR_O,
  output Vld_O
 
  );
  
  localparam logic[31:0] IV [0:7] = {
    `IV_0, `IV_1, `IV_2, `IV_3,
    `IV_4, `IV_5, `IV_6, `IV_7
  };
  
   // states for the FSM
  typedef enum {IDLE, FIRST_BLOCK, MIDDLE_BLOCKS, LAST_BLOCK} state_t;
 
  state_t next_state;
  state_t state;
  
  //flags
  bit chunk_start;
  bit chunk_end;
  bit root;
  
  //valid shift register & it's pulse
  bit vld;
  bit [2:0] vld_shr;
  
  // byte counter
  bit [10:0] byte_cntr;
  // the number of bytes left from the chunk
  bit [10:0] byte_left;
  
  // number of bytes in the block
  bit [31:0] byte_len;
  
  // start register
  bit strt;
  
  bit next;
  
  //last block
  bit last_blk;
  
  // update register
  bit upd;
  
  // input chaining value registers
  bit [7:0] [31:0] chain_val;
  
  
  //hash output
  bit [7:0] [31:0] hash;
  bit [7:0] [31:0] hash_reg;
  
  //valid output register
  bit vld_out_reg;
  
  // counter of clock cycles in hashing
  bit [$clog2(HASH_DELAY)-1:0] cc_cntr;
  bit end_of_block;
  bit almost_end_of_block;
  bit en;
  bit dbl_hash;
  bit dbl_hash_pulse;
  bit end_of_dbl_hash;
  bit dbl_hash_rdy;
  
  
  HashGen #(
    .HASH_DELAY(HASH_DELAY)
    )HashGen_i (
    .Clk(Clk),
    .Strt_I(strt),
    .Clear_I(Clear_I),
    .EN_I(en),
    .BL_I(byte_len),
    .CS_flg_I(chunk_start),
    .CE_flg_I(chunk_end),
    .ROOT_flg_I(root),
    .H_I(chain_val),
    .Msg_I(Msg_I),
    .Vld_O(vld),
    .CNTR_O(cc_cntr),
    .H_O(hash)
  );
  
  assign end_of_block = (cc_cntr==HASH_DELAY);
  assign almost_end_of_block = (cc_cntr==(HASH_DELAY-1));
  assign CNTR_O = cc_cntr;
  
////////////////////
// Update register //
////////////////////

  always_ff@(posedge Clk or negedge Rst_n)
  begin : update_reg
    if(~Rst_n)
      upd  <= 1'b0;
    else 
      upd <= Update_I;
  end


////////////////////
// Valid registers //
////////////////////

  assign vld_shr[0] = (!upd && !strt) ? vld : 1'b0;

  always_ff@(posedge Clk or negedge Rst_n)
  begin : valid_reg
    if(~Rst_n)
      vld_shr[2:1] <= 2'b00;
    else if(Update_I)
      vld_shr[2:1] <= 2'b00;
    else 
      vld_shr[2:1] <= vld_shr[1:0];
  end
  
  
  always_ff@(posedge Clk or negedge Rst_n)
  begin : valid_output
    if(~Rst_n)
      vld_out_reg  <= 1'b0;
    else if(Update_I)
      vld_out_reg <= 1'b0;
    else if(vld_shr[2:1]==2'b01 && last_blk)
      vld_out_reg <= 1'b1;

  end
  
  assign Vld_O = next && last_blk;
  
/////////////////////////
// Start hash register //
/////////////////////////

  assign dbl_hash_pulse = (almost_end_of_block && (~dbl_hash) && (state==LAST_BLOCK));

  always_ff@(posedge Clk or negedge Rst_n)
  begin : start_reg
    if(~Rst_n)
      strt  <= 1'b0;
    //new message block is ready or the chunk has been updated
    else if((almost_end_of_block))// && !last_blk) || Update_I || dbl_hash_pulse)
      strt <= 1'b1;
    else
      strt <= 1'b0;
  end
                                                           
  
//////////////////
// Byte counter //
//////////////////

  always_ff@(posedge Clk or negedge Rst_n)
  begin : byte_counter
    if(~Rst_n)
      byte_cntr <= 11'h000;
    // new hash is initiated
    else if(Update_I || dbl_hash || end_of_dbl_hash)
      byte_cntr <= 11'h000;
    // adding 64 byte after every hash
    else if(end_of_block)
      byte_cntr <= byte_cntr + 8'h40;
  end
  
  assign byte_left = Byte_num_I - byte_cntr;
  assign byte_len = (byte_left < 8'h40) ? {21'h00_0000, byte_left} : 32'h0000_0040;
  
  // Next message request
  always_ff@(posedge Clk or negedge Rst_n)
  begin : next_pulse
    if(~Rst_n)
      next <= 0;
    else
      next <= (almost_end_of_block);
  end
  
  assign Next_O = next;
///////////////////////////
// Hash output registers //
///////////////////////////

  always_ff@(posedge Clk or negedge Rst_n)
  begin : hash_register
    if(~Rst_n)
      hash_reg <= 0;
    //hash output is valid
    else
      hash_reg <= hash;
  end
  
  assign H_O = hash_reg;
 
  
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
      
      FIRST_BLOCK, MIDDLE_BLOCKS: begin
        if(Update_I)
          next_state <= FIRST_BLOCK;
        else if(Clear_I)
          next_state <= IDLE;
        else if(almost_end_of_block) begin
          if(byte_left <= 8'h40)
            next_state <= FIRST_BLOCK;
          // less than 64 bytes
          else if(byte_left <= 8'h80)
            next_state <= LAST_BLOCK;
          else
            next_state <= MIDDLE_BLOCKS;
        end
      end//FIRST_BLOCK, MIDDLE_BLOCKS

      LAST_BLOCK: begin
        if(Update_I)
          next_state <= FIRST_BLOCK;
        else if(Clear_I)
          next_state <= IDLE;
        else if(almost_end_of_block) begin
          if(~dbl_hash)
            next_state <= FIRST_BLOCK;
          else
            next_state <= IDLE;
        end
      end//LAST_BLOCK

      default:
          next_state <= state;
    endcase
  end
  
  integer i;
  
  //sequential FSM
  always_ff@(posedge Clk or negedge Rst_n)
  begin : fsm_seq
    if(~Rst_n) begin
      last_blk <= 1'b0;
      en <= 1'b0;
      dbl_hash <= 1'b0;
    end  
    else begin
      last_blk <= 1'b0;
      en <= 1'b0;
      case (state)
        
        FIRST_BLOCK: begin
          en <= 1'b1;
          dbl_hash <= 1'b0;
          //the chunk is 1 block
          if(byte_left <= 8'h40) begin
            last_blk <= 1'b1;
          end
        end

        MIDDLE_BLOCKS: begin
          en <= 1'b1;
        end
        
        LAST_BLOCK: begin
          en <= 1'b1;
          last_blk <= 1'b1;
          if(almost_end_of_block)
            dbl_hash <= 1'b1;
        end
        
        default: begin
          en <= 1'b0;
          last_blk <= 1'b0;
        end
        
      endcase
    end
  end
  
  assign end_of_dbl_hash = (last_blk && state==FIRST_BLOCK && end_of_block && !dbl_hash);
  
  always_ff@(posedge Clk or negedge Rst_n)
  begin : flag_regs
    if(~Rst_n) begin
      chunk_end <= 1'b0;
      root <= 1'b0;
    end
    //new block or new double hash cycle
    else if(Update_I || end_of_dbl_hash) begin
      chunk_end <= 1'b0;
      root <= 1'b0;
    end
    else if(state==LAST_BLOCK) begin
      chunk_end <= 1'b1;
      root <= 1'b1;
    end
  end
  
  always_ff@(posedge Clk or negedge Rst_n)
  begin : chunk_start_reg
    if(~Rst_n)
      chunk_start <= 0;
    else if(Update_I || dbl_hash)
      chunk_start <= 1'b1;
    else if(state!=FIRST_BLOCK)
      chunk_start <= 0;
  end
  
  always_ff@(posedge Clk or negedge Rst_n)
  begin : chain_val_regs
    if(~Rst_n)
      chain_val <= 0;
    else if(Update_I || dbl_hash) begin
      // the chaining values are equal to the initialization values
      for (i = 0; i < 8; i++)
        chain_val[i] <= IV[i];
    end
    else if(state inside {MIDDLE_BLOCKS,LAST_BLOCK})
      chain_val <= hash;
  end
  
endmodule : ChunkHasher