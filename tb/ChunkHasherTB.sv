`include "../src/defines.sv"

module ChunkHasherTB;
  parameter test_name1 = "test.txt";
  parameter test_name2 = "test.txt";

  localparam logic[31:0] IV [0:7] = {
    `IV_0, `IV_1, `IV_2, `IV_3,
    `IV_4, `IV_5, `IV_6, `IV_7
  };

  logic clk, rst_n, strt;
  
  logic [1:0] vld;
  
  logic [15:0] [31:0] M_I;
  logic [7:0] [31:0] H_O;
  logic [7:0] [31:0] hw;
  
  logic [9:0] addr;
  
  int fd;
  int msg_idx = 0;
  logic [31:0] byte_length = 0;
  
  shortint clk_cntr = 0;
  
  string tn1 = {"C:/Alephium/Git/fpga-miner/test_vectors/", test_name1};
  string tn2 = {"C:/Alephium/Git/fpga-miner/test_vectors/", test_name2};
  string line;
  bit eof = 0;
  
  //initial chaining value
  genvar i;
  generate
    for (i = 0; i < 8; i++)
    begin
      assign hw[i] = IV[i];
    end
  endgenerate  

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
  
  // counting the number of words in the test vector file
  task count_data(string test_name);
  
    byte_length = 0;
  
    //counting the lines
    fd = $fopen(test_name, "r");
    eof = 0;
    
    while (!eof) begin
      $fgets(line, fd);
      byte_length = byte_length + 4;
      eof = $feof(fd);
    end

    $fclose(fd);
  
  endtask : count_data
  
  // chunk hashing task
  task chunk_hash(string test_name);
    
    //reading the actual data from the file
    fd = $fopen(test_name, "r");
    eof = 0;
 
    
    while (!eof) begin
      msg_idx = 0;
      
      // Scanning for message blocks until the end of the file
      while (!eof && msg_idx < 16) begin
        $fscanf(fd, "%h\n", M_I[msg_idx]);
        msg_idx++;
        eof = $feof(fd);
      end
      
      if(msg_idx < 15) begin
        for(int idx = msg_idx; idx < 16; idx++)
          M_I[idx] = 0;
      end
      
      // end of file -> close this file handle
      if(eof)
        $fclose(fd);
        
      // 1 cc start pulse
      if(addr==10'h000 || vld[0])
        start_pulse();
      
      if(!eof)
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
      $display("Final hash: %s", strvar);
    end
  end
  
  initial
  begin
    
    count_data(tn1);
    
    strt = 1'b0;
    rst_n = 1'b1;
    #100;
    // reset
    rst_n = 1'b0;
    #28;
    rst_n = 1'b1;
    #100;
    chunk_hash(tn1);
    #100;
    count_data(tn2);
    chunk_hash(tn2);
    #100;
    
    $display("End of simulation time is %d ",$time);
    $finish;
  end
  
endmodule : ChunkHasherTB