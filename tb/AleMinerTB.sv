
module AleMinerTB;

  parameter byte_num = 328;

  logic clk, rst_n, strt, wr, irq;
  
  logic [1:0] vld;
  
  logic [7:0] data_byte;
  
  logic [31:0] data;
  
  logic [31:0] group_directions;
  logic [31:0] groups;
  
  logic [5:0][31:0] nonce_in;
  logic [5:0][31:0] nonce_out;
  
  logic [7:0][31:0] target;
  logic [7:0][31:0] hash;
  
  logic [31:0] byte_length = byte_num-2;
 
  int clk_cntr = 0;
  
  logic [31:0] hash_cntr;
  
  shortint data_cntr;
  
  logic clr = 0;
  
  
  AleMiner DUT
  (
    .Clk(clk),
    .Rst_n(rst_n),
    .UpdateTrigger_I(strt),
    .GroupDirections_I(group_directions),
    .Groups_I(groups),
    .ChunkLength_I(byte_length),
    .Target_I(target),
    .Nonce_I(nonce_in),
    .Wr_I(wr),
    .Data_I(data),
    .VldNonce_O(vld[0]),
    .Nonce_O(nonce_out),
    .HashCounter_O(hash_cntr),
    .Hash_O(hash),
    .Irq_O(irq) 
  );
    
  
  initial clk = 0;
  always #5 clk = ~clk;
  
  // valid shift register
  always@(posedge clk)
  begin : valid_shr
    vld[1] <= vld[0];
  end 
  
  // start pulse generator
  task start_pulse;
    @(negedge clk);
    strt = 1'b1;
    @(negedge clk);
    strt = 1'b0;
  endtask : start_pulse
  
  task write_cycle;
  
    data_cntr = 0;
    clr = 1;
    #20;
    clr = 0;
    start_pulse();
    
    @(posedge clk);
    #2;
    wr = 1;
    while(data_cntr <= (byte_num - 28)) begin
      @(posedge clk);
      data_cntr = data_cntr + 4;
    end
    #2;
    wr = 0;
  
  endtask : write_cycle
  
  
  // message generator
  always@(posedge clk)
  begin : msg_gen
    if(~rst_n) begin
      data_byte <= 8'h18;   
    end
    else if(clr)
      data_byte <= 8'h18;
    else if(wr) begin
      if(data_byte < 247)
        data_byte <= data_byte + 4;
      else
        data_byte <= data_byte%247;
    end
  end
  
  assign data[7:0] =    data_byte;
  assign data[15:8] =  (data_byte < 250) ? data_byte + 1 : 0;
  assign data[23:16] = (data_byte < 249) ? data_byte + 2 : data_byte%249;
  assign data[31:24] = (data_byte < 248) ? data_byte + 3 : data_byte%248;
  //
  always@(posedge clk)
  begin : clock_counter
    if(strt)
      clk_cntr <= 0;
    else if(DUT.rdy_hash==2'b01)
      clk_cntr <= 0;
    else if(!vld[0])
      clk_cntr++;
  end
  
  
  
  initial
  begin
    
    strt = 1'b0;
    rst_n = 1'b1;
    wr = 0;
    #100;
    // reset
    rst_n = 1'b0;
    #28;
    rst_n = 1'b1;
    #100;
    
    group_directions = 0;
    group_directions[23:16] = 2;
    group_directions[7:0] = 3;
    groups = 0;
    groups[23:16] = 4;
    groups[15:8] = 16;
    groups[7:0] = 2;
    
    nonce_in[0] = 32'h14151617;
    nonce_in[1] = 32'h10111213;
    nonce_in[2] = 32'h0C0D0E0F;
    nonce_in[3] = 32'h08090A0B;
    nonce_in[4] = 32'h04050607;
    nonce_in[5] = 32'h00010203;
    
    target[0] = 32'h0;
    target[1] = 32'h1;
    target[2] = 32'h2;
    target[3] = 32'h3;
    target[4] = 32'h4;
    target[5] = 32'h5;
    target[6] = 32'h6;
    target[7] = 32'hf0010000;
    
    #100;
    
    write_cycle();

    
    while(irq!=1'b1) begin
      if(vld[0]) begin
        $display("%d Nonce: %0h valid: %b conditions: %b", hash_cntr, (nonce_out-1), vld, DUT.Miner_i.conditions);
        $display("Hash: %0h ", DUT.hash);
      end
      @(posedge clk);
      @(posedge clk);
    end 
    $display("start_pulseFinal nonce: %0h hash: %0h ", nonce_out, {hash[7],hash[6],hash[5],hash[4],hash[3],hash[2],hash[1],hash[0]});
    #500;
    #1000;
    
    write_cycle();

    #10000;
    
    target[7] = 32'h0A010000;
    
    write_cycle();
    
    #10000;
    
    $display("End of simulation time is %d ",$time);
    $finish;
  end
  
endmodule : AleMinerTB