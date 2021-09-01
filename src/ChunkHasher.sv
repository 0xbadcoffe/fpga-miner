// === ChunkHasher.sv ===

`include "defines.sv"

module ChunkHasher
  (
  // Clock & Reset
  input Clk,
  input Rst_n,
  // Inputs
  // Memory inputs
  input Update_I,
  input [15:0] [31:0] Msg_I,
  // Number of Bytes in the chunk
  // Max 1024
  input [10:0] Byte_num_I,
  
  // Outputs
  //FIFO outputs
  output Next_O,
  
  //final result
  output [7:0] [31:0] H_O,
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
  
  HashGen HashGen_i(
    .Clk(Clk),
    .Strt_I(strt),
    .BL_I(byte_len),
    .CS_flg_I(chunk_start),
    .CE_flg_I(chunk_end),
    .ROOT_flg_I(root),
    .H_I(chain_val),
    .Msg_I(Msg_I),
    .Vld_O(vld),
    .H_O(hash)
  );
  
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
  
  assign Vld_O = vld_out_reg;
  
/////////////////////////
// Start hash register //
/////////////////////////

  always_ff@(posedge Clk or negedge Rst_n)
  begin : start_reg
    if(~Rst_n)
      strt  <= 1'b0;
    //new message block is ready or the chunk has been updated
    else if((vld_shr[2:1]==2'b01 && !last_blk) || Update_I)
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
    else if(Update_I)
      byte_cntr <= 11'h000;
    // adding 64 byte after every hash
    else if(vld_shr[1:0] == 2'b01)
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
      next <= (vld_shr[2:1] == 2'b01);
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
    else if(vld_shr[2:1]==2'b01)
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
  always@(upd, vld_shr[2]) 
  begin : next_state_decode
    next_state <= state;
    case (state)
    
      IDLE: begin
        if(upd)
          next_state <= FIRST_BLOCK;
      end//IDLE
      
      FIRST_BLOCK, MIDDLE_BLOCKS: begin
        if(upd)
          next_state <= FIRST_BLOCK;
        else if(vld_shr[2]) begin
          if(byte_cntr >= Byte_num_I)
            next_state <= IDLE;
          // less than 64 bytes
          else if(byte_left <= 8'h40)
            next_state <= LAST_BLOCK;
          else
            next_state <= MIDDLE_BLOCKS;
        end
      end//FIRST_BLOCK, MIDDLE_BLOCKS

      LAST_BLOCK: begin
        if(upd)
          next_state <= FIRST_BLOCK;
        else if(vld_shr[2])
          next_state <= IDLE;
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
      chunk_start <= 1'b0;
      chunk_end <= 1'b0;
      root <= 1'b0;
      last_blk <= 1'b0;
      chain_val <= 0;
    end  
    else begin
      chunk_start <= 1'b0;
      chunk_end <= 1'b0;
      root <= 1'b0;
      last_blk <= 1'b0;
      case (state)
        
        FIRST_BLOCK: begin
          chunk_start <= 1'b1;
          // the chaining values are equal to the initialization values
          for (i = 0; i < 8; i++)
            chain_val[i] <= IV[i];
          //the chunk is 1 block
          if(byte_left <= 8'h40) begin
            chunk_end <= 1'b1;
            root <= 1'b1;
            last_blk <= 1'b1;
          end
        end

        MIDDLE_BLOCKS: begin
          chain_val <= hash_reg;
        end
        
        LAST_BLOCK: begin
          chunk_start <= 1'b0;
          chunk_end <= 1'b1;
          root <= 1'b1;
          last_blk <= 1'b1;
          chain_val <= hash_reg;
        end
        
        default: begin
          chunk_start <= 1'b0;
          chunk_end <= 1'b0;
          root <= 1'b0;
          last_blk <= 1'b0;
          chain_val <= 0;
        end
        
      endcase
    end
  end
  
  
endmodule : ChunkHasher