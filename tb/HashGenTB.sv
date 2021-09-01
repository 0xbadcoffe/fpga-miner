`include "../src/defines.sv"

module HashGenTB; 

  localparam logic[31:0] IV [0:7] = {
    `IV_0, `IV_1, `IV_2, `IV_3,
    `IV_4, `IV_5, `IV_6, `IV_7
  };

  logic clk,strt,vld;
  
  logic [15:0] [31:0] M_I;
  logic [7:0] [31:0] H_O;
  logic [7:0] [31:0] hw;
  
  int fd;
  int msg_idx = 0;
  logic [31:0] byte_length = 0;
  
  shortint clk_cntr = 0;
  
  //initial chaining value
  genvar i;
  generate
    for (i = 0; i < 8; i++)
    begin
      assign hw[i] = IV[i];
    end
  endgenerate  


  HashGen DUT(
  .Clk(clk),
  .Strt_I(strt),
  .BL_I(byte_length),
  .CS_flg_I(1'b1),
  .CE_flg_I(1'b1),
  .ROOT_flg_I(1'b1),
  .H_I(hw),
  .Msg_I(M_I),
  .Vld_O(vld),
  .H_O(H_O)
  );
  
  initial clk = 0;
  always #5 clk = ~clk;
  
  always@(posedge clk)
  begin : clock_counter
    if(strt)
      clk_cntr <= 0;
    else if(!vld)
      clk_cntr++;
  end
  
  initial
  begin
  
    fd = $fopen("C:/Alephium/Git/fpga-miner/test_vectors/test.txt", "r");
    
    // Scanning for message blocks until the end of the file
    while (!$feof(fd)) begin
      $fscanf(fd, "%h\n", M_I[msg_idx]);
      msg_idx++;
      byte_length = byte_length + 4;
    end
    
    // close this file handle
    $fclose(fd);
    
    strt = 1'b0;
    #100;
    // 1 cc start pulse
    strt = 1'b1;
    #10;
    strt = 1'b0;
    #1000;
    // 1 cc start pulse
    strt = 1'b1;
    #10;
    strt = 1'b0;
    #5000;
    $display("End of simulation time is %d ",$time);
    $finish;
  end
  
endmodule : HashGenTB