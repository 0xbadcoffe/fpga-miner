
module MinerTB;
  parameter byte_num = 288;

  logic clk, rst_n, strt, next;
  
  logic [1:0] vld;
  
  logic [1:0] rdy;
  
  logic [7:0] msg_byte;
  
  logic [31:0] M_I;
  
  logic [191:0] nonce;
  
  logic [255:0] target;
  
  logic [31:0] byte_length = byte_num;
 
  int clk_cntr = 0;
  
  int hash_cntr = 0;
  
  
  Miner DUT
  (
    .Clk(clk),
    .Rst_n(rst_n),
    .Update_I(strt),
    .Msg_I(M_I),
    .ByteNum_I(byte_length),
    .FromGroup_I(2),
    .ToGroup_I(3),
    .Nonce_I(nonce),
    .Groups_I(4), //4
    .ChainNum_I(16), //16
    .GroupsShifter_I(2),
    .Target_I(target),
    .Next_O(next),
    .Vld_O(vld[0]),
    .Rdy_O(rdy[0])
  );
  
  
  assign target[31:0] = 32'hffffffff;
  assign target[63:32] = 32'hffffffff;
  assign target[95:64] = 32'hffffffff;
  assign target[127:96] = 32'hffffffff;
  assign target[159:128] = 32'hffffffff;
  assign target[191:160] = 32'h0fffffff;
  assign target[223:192] = 32'h00000000;
  assign target[255:224] = 32'h1f010000;
  
  

  
  initial clk = 0;
  always #5 clk = ~clk;
  
  // valid shift register
  always@(posedge clk)
  begin : valid_shr
    vld[1] <= vld[0];
    rdy[1] <= rdy[0];
  end 
  
  // start pulse generator
  task start_pulse;
    @(negedge clk);
    strt = 1'b1;
    @(negedge clk);
    strt = 1'b0;
  endtask : start_pulse
  
  
  // message generator
  always@(posedge clk)
  begin : msg_gen
   if(~rst_n)
    msg_byte <= 8'h18;
   else if(rdy==2'b01 && vld==2'b00)
    msg_byte <= 8'h18;
   else if(next)
    if(msg_byte < 247)
      msg_byte <= msg_byte + 4;
    else
      msg_byte <= msg_byte%247;
  end
  
  assign M_I[7:0] = msg_byte;
  assign M_I[15:8] = (msg_byte < 250) ? msg_byte + 1 : 0;
  assign M_I[23:16] = (msg_byte < 249) ? msg_byte + 2 : msg_byte%249;
  assign M_I[31:24] = (msg_byte < 248) ? msg_byte + 3 : msg_byte%248;
  //
  always@(posedge clk)
  begin : clock_counter
    if(strt)
      clk_cntr <= 0;
    else if(rdy==2'b11)
      clk_cntr <= 0;
    else if(!vld[0])
      clk_cntr++;
  end
  
  always@(posedge clk)
  begin : nonce_counter
    if(~rst_n) begin
      nonce[31:0]    <= 32'h14151617;
      nonce[63:32]   <= 32'h10111213;
      nonce[95:64]   <= 32'h0C0D0E0F;
      nonce[127:96]  <= 32'h08090A0B;
      nonce[159:128] <= 32'h04050607;
      nonce[191:160] <= 32'h00010203;
    end
    else if(rdy==2'b01 && vld==2'b00)
      nonce++;
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
    while(vld!=2'b01) begin
      start_pulse();
      @(posedge DUT.vld_hash[0]);
      //while(DUT.vld_hash!=2'b11)
      //  @(posedge clk);
      //$display("%0d Hash: %0h", hash_cntr, DUT.hash);
      @(posedge rdy);
      if(DUT.conditions!=0) begin
        $display("%0d Nonce: %0h valid: %b",hash_cntr, nonce, vld);
        $display("Final hash: %0h conditions: %b", DUT.hash, DUT.conditions);
      end
      hash_cntr++;
    end 
    #1000;
    
    $display("End of simulation time is %d ",$time);
    $finish;
  end
  
endmodule : MinerTB