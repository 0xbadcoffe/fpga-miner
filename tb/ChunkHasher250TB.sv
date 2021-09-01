`include "../src/defines.sv"

module ChunkHasher250TB;
  parameter byte_num = 150;

  logic clk, rst_n, strt;
  
  logic [1:0] vld;
  
  logic [15:0] [31:0] M_I;
  logic [7:0] [31:0] H_O;
  logic [7:0] [31:0] hw;
  logic [255:0] hash;
  
  logic [9:0] addr;
  
  logic [31:0] byte_length = byte_num;
  
  shortint clk_cntr = 0;
  
  
  shortint byte_cntr;
  shortint msg_idx;
  logic [7:0] msg_val;
  shortint msg_mod;
  
  

  ChunkHasher DUT
  (
    .Clk(clk),
    .Rst_n(rst_n),
    .Update_I(strt),
    .Msg_I(M_I),
    .Byte_num_I(byte_length),
    .Addr_O(addr),
    .H_O(H_O),
    .Vld_O(vld[0])
  );
  

  assign hash[255:224] = {<<8{H_O[0]}};
  assign hash[223:192] = {<<8{H_O[1]}};
  assign hash[191:160] = {<<8{H_O[2]}};
  assign hash[159:128] = {<<8{H_O[3]}};
  assign hash[127:96] = {<<8{H_O[4]}};
  assign hash[95:64] = {<<8{H_O[5]}};
  assign hash[63:32] = {<<8{H_O[6]}};
  assign hash[31:0] = {<<8{H_O[7]}};

  
  initial clk = 0;
  always #5 clk = ~clk;
  
  // valid shift register
  always@(posedge clk)
  begin : valid_shr
    vld[1] <= vld[0];
  end 
  
  // start pulse generator
  task start_pulse;
    strt = 1'b1;
    #10;
    strt = 1'b0;
  endtask : start_pulse
  

  
  // chunk hashing task
  task chunk_hash;
  
    byte_cntr = 0;   
    msg_val = 0;
       
    while (byte_cntr!=byte_num) begin
      msg_idx = 0;
      
      // Scanning for message blocks until the end of the byte_num
      while (byte_cntr!=byte_num && msg_idx < 16) begin
        msg_mod = byte_cntr%4;
        if(msg_mod==0) begin
          M_I[msg_idx] = 0;
          M_I[msg_idx][7:0] = msg_val;
        end
        else if(msg_mod==1) begin
          M_I[msg_idx][15:8] = msg_val;
          M_I[msg_idx][31:16] = 0;
        end
        else if(msg_mod==2) begin 
          M_I[msg_idx][23:16] = msg_val;
          M_I[msg_idx][31:24] = 0;
        end
        else begin
          M_I[msg_idx][31:24] = msg_val;
          msg_idx++;
        end
        //msg_val counter
        if(msg_val==250)
          msg_val = 0;
        else
          msg_val++;
        byte_cntr++;
      end
      
      
      if(msg_idx < 15 && msg_mod < 3)
        msg_idx++;
      
      if(msg_idx < 15 || msg_mod==3) begin
        for(int idx = msg_idx; idx < 16; idx++)
          M_I[idx] = 0;
      end
        
      // 1 cc start pulse
      if(addr==10'h000 || vld[0])
        start_pulse();
      
      if(byte_cntr != byte_num)
        @(addr);
      else begin
        @(posedge vld[0]);
        #50;
      end    
    end
    
  endtask : chunk_hash
  
  //
  always@(posedge clk)
  begin : clock_counter
    if(strt)
      clk_cntr <= 0;
    else if(!vld[0])
      clk_cntr++;
  end
  
  //
  always@(posedge clk)
  begin : hash_display
    string strvar = "";
    if(vld == 2'b01) begin
      foreach(H_O[i])
        strvar = {$sformatf("%0h ", H_O[i]), strvar};
      $display("Final state: %s", strvar);
      $display("Hash: %0h", hash);
    end
  end
  
  initial
  begin
    
    strt = 1'b0;
    rst_n = 1'b1;
    #100;
    // reset
    rst_n = 1'b0;
    #28;
    rst_n = 1'b1;
    #100;
    chunk_hash();
    #100;
    
    $display("End of simulation time is %d ",$time);
    $finish;
  end
  
endmodule : ChunkHasher250TB