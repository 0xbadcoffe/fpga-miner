// === AleMiner.sv ===

module AleMiner
  //262 bytes -> 66 addresses
  #(parameter ADDR_WIDTH = 7)
  (
  // Clock & Reset
  input Clk,
  input Rst_n,
  // Register inputs
  input UpdateTrigger_I,
  input [31:0] GroupDirections_I,
  input [31:0] Groups_I,
  input [31:0] ChunkLength_I,
  input [7:0][31:0] Target_I,
  input [5:0][31:0] Nonce_I,
  // Memory inputs
  input Wr_I,
  input [31:0] Data_I,
  
  //Registe outputs
  output VldNonce_O,
  output [5:0][31:0] Nonce_O,
  output [7:0][31:0] Hash_O,
  
  output [31:0] HashCounter_O,
  
  // interrupt
  output Irq_O
  
  //ILA
  //output [255:0] MinerHash_O,
  //output VldHash_O,
  //output [2:0] Cond_O,
  //output [6:0] RdAddr_O,
  //output RD_O,
  //output EOM_O
  
  );
  
  // end of writing the memory
  // start of a new mining cycle
  logic endOfMemory;
  logic strt;
  
  //updating the memory
  logic update;
  
  //number of words in the memory
  logic [ADDR_WIDTH-1:0] wordNum;
  
  // target difficulty
  logic [255:0] target;
  logic [191:0] nonce;
  logic [255:0] hash;
  logic [255:0] final_hash;
  
  // group registers
  logic [7:0] groups; //4
  logic [7:0] chain_num; //16 Grroups*Groups
  logic [7:0] groups_shr;//2
  
  logic [7:0] from_group;
  logic [7:0] to_group;
  
  logic [1:0] vld_hash;
  logic [1:0] rdy_hash;
  
  //Memory signals
  (* ram_style = "block" *) logic [31:0] memory [2**ADDR_WIDTH-1:0];
  logic [ADDR_WIDTH-1:0] wrAddr;
  logic [ADDR_WIDTH-1:0] rdAddr;
  
  logic [31:0] msg;
  logic rd;
  
  // hashing cycle finished without valid result
  logic invld_hash;
  logic vld_nonce;
  
  logic irq;
  
  logic [31:0] hash_cntr;
  
  //ILA
  //logic [2:0] conditions;
  
  // Target Difficulty
  assign target[31:0]    = Target_I[0];
  assign target[63:32]   = Target_I[1];
  assign target[95:64]   = Target_I[2];
  assign target[127:96]  = Target_I[3];
  assign target[159:128] = Target_I[4];
  assign target[191:160] = Target_I[5];
  assign target[223:192] = Target_I[6];
  assign target[255:224] = Target_I[7];
  
  
  // Number of messages to be hashed
  // byte number = nonce + messages
  assign wordNum = ((ChunkLength_I-24)>>2);
  
/////////////////// 
// Memory Update //
///////////////////

  always_ff@(posedge Clk or negedge Rst_n)
  begin : memory_update
    if(~Rst_n) begin
      update <= 0;
      endOfMemory <= 0;
    end
    else if(UpdateTrigger_I) begin
      update <= 1'b1;
      endOfMemory <= 0;
    end
    else if(wrAddr==(wordNum-1) && Wr_I) begin
      update <= 0;
      endOfMemory <= 1'b1;
    end
    else
      endOfMemory <= 0;
  end
  
///////// 
// RAM //
/////////

  always_ff@(posedge Clk)
  begin : RAM
    if (Wr_I) // write data to address 'addr'
      memory[wrAddr] <= Data_I;
  end
  
  assign msg = memory[rdAddr];
  
  always_ff@(posedge Clk or negedge Rst_n)
  begin : write_address
    if(~Rst_n)
      wrAddr <= 0;
    else if(UpdateTrigger_I)
      wrAddr <= 0;
    else if(Wr_I)
      wrAddr++;
  end
  
  always_ff@(posedge Clk or negedge Rst_n)
  begin : read_address
    if(~Rst_n)
      rdAddr <= 0;
    else if(endOfMemory || invld_hash)
      rdAddr <= 0;
    else if(rd && !update)
      rdAddr++;
  end
  
///////////////////////// 
// Start of Hash Cycle //
/////////////////////////

  always_ff@(posedge Clk or negedge Rst_n)
  begin : start_of_hash
    if(~Rst_n)
      strt <= 0;
    else
      strt <= endOfMemory || invld_hash;
  end
  
  Miner Miner_i
  (
    .Clk(Clk),
    .Rst_n(Rst_n),
    .Update_I(strt),
    .Clear_I(UpdateTrigger_I),
    .Msg_I(msg),
    .ByteNum_I(ChunkLength_I[10:0]),
    .FromGroup_I(from_group),
    .ToGroup_I(to_group),
    .Nonce_I(nonce),
    .Groups_I(groups), //4
    .ChainNum_I(chain_num), //16
    .GroupsShifter_I(groups_shr),
    .Target_I(target),
    .Next_O(rd),
    .Vld_O(vld_hash[0]),
    .Rdy_O(rdy_hash[0]),
    .Hash_O(hash)
    //ILA
    //.Cond_O(conditions)
  );
  
  
  
  assign invld_hash = (rdy_hash==2'b01 && vld_hash==0);
  
//////////////////////////////// 
// Valid/Ready Shift Register //
////////////////////////////////

  always_ff@(posedge Clk or negedge Rst_n)
  begin : valid_shr
    if(~Rst_n) begin
      rdy_hash[1] <= 1'b0;
      vld_hash[1] <= 1'b0;
    end
    else begin
      rdy_hash[1] <= rdy_hash[0];
      vld_hash[1] <= vld_hash[0];
    end
  end
  
/////////////////// 
// Hash Counter //
///////////////////

  always_ff@(posedge Clk or negedge Rst_n)
  begin : hash_counter
    if(~Rst_n)
      hash_cntr <= 0;
    else if(UpdateTrigger_I)
      hash_cntr <= 0;
    else if(rdy_hash==2'b01)
      hash_cntr++;
  end
  
  assign HashCounter_O = hash_cntr;
  
/////////////////// 
// Nonce Counter //
///////////////////

  always_ff@(posedge Clk or negedge Rst_n)
  begin : nonce_counter
    if(~Rst_n) begin
      nonce <= 0;
      groups <= 0;
      chain_num <= 0;
      groups_shr <= 0;
      from_group <= 0;
      to_group <= 0;
    end
    else if(UpdateTrigger_I) begin
      nonce[31:0]  <= Nonce_I[0];
      nonce[63:32] <= Nonce_I[1];
      nonce[95:64] <= Nonce_I[2];
      nonce[127:96]  <= Nonce_I[3];
      nonce[159:128] <= Nonce_I[4];
      nonce[191:160] <= Nonce_I[5];
      groups <= Groups_I[23:16];
      chain_num <= Groups_I[15:8];
      groups_shr <= Groups_I[7:0];
      from_group <= GroupDirections_I[23:16];
      to_group <= GroupDirections_I[7:0];
    end
    // hashing cycle finished without valid result
    // no memory update ungoing
    else if(invld_hash && !update)
      nonce++;
  end
  
  always_ff@(posedge Clk or negedge Rst_n)
  begin : valid_nonce
    if(~Rst_n) begin
      vld_nonce <= 0;
      irq <= 1'b0;
      final_hash <= {256{1'b1}};
    end
    // new mining cycle
    else if(UpdateTrigger_I) begin
      vld_nonce <= 1'b0;
      irq <= 1'b0;
      final_hash <= {256{1'b1}};
    end
    // valid hash has been found
    else begin
      if (rdy_hash==2'b01 && vld_hash==2'b01) begin
        final_hash <= hash;
        vld_nonce <= 1'b1;
        irq <= 1'b1;
      end
      else
        vld_nonce <= 0;
    end
  end
  
  assign VldNonce_O = vld_nonce;
  assign Irq_O = irq;
  
  assign Nonce_O[0] = nonce[31:0];
  assign Nonce_O[1] = nonce[63:32];
  assign Nonce_O[2] = nonce[95:64];
  assign Nonce_O[3] = nonce[127:96]; 
  assign Nonce_O[4] = nonce[159:128];
  assign Nonce_O[5] = nonce[191:160];
  
  assign Hash_O[0] = final_hash[31:0];
  assign Hash_O[1] = final_hash[63:32];
  assign Hash_O[2] = final_hash[95:64];
  assign Hash_O[3] = final_hash[127:96]; 
  assign Hash_O[4] = final_hash[159:128];
  assign Hash_O[5] = final_hash[191:160];
  assign Hash_O[6] = final_hash[223:192];
  assign Hash_O[7] = final_hash[255:224];
  
  //ILA
  //assign MinerHash_O = hash;
  //assign VldHash_O = vld_hash[0];
  //assign EOM_O = endOfMemory;
  //assign RdAddr_O = rdAddr;
  //assign RD_O = rd;
  //assign Cond_O = conditions;
  
  
endmodule : AleMiner