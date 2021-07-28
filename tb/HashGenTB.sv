`include "defines.sv"

module HashGenTB;  

  localparam logic[31:0] IV [0:7] = {
    `IV_0, `IV_1, `IV_2, `IV_3,
    `IV_4, `IV_5, `IV_6, `IV_7
  };

  logic clk,strt,vld;
  
  logic [31:0] M_I [0:15];
  logic [31:0] H_O [0:7];
  logic [7:0] [31:0] hw;
  
  //initial chaining value
  genvar i;
  generate
    for (i = 0; i < 8; i++)
    begin
      assign hw[i] = IV[i];
    end
  endgenerate
    
  
  // message block
  //m0-m15
  genvar j;
  generate
    for (j = 0; j < 16; j = j + 1)
    begin
      assign M_I[j] = j*32'h55;
    end
  endgenerate
  


  HashGen DUT(
  .Clk(clk),
  .Strt_I(strt),
  .BL_I(32'd64),
  .CS_flg_I(1'b1),
  .CE_flg_I(1'b0),
  .ROOT_flg_I(1'b0),
  .H_I(hw),
  .Msg0_I(M_I[0]),
  .Msg1_I(M_I[1]),
  .Msg2_I(M_I[2]),
  .Msg3_I(M_I[3]),
  .Msg4_I(M_I[4]),
  .Msg5_I(M_I[5]),
  .Msg6_I(M_I[6]),
  .Msg7_I(M_I[7]),
  .Msg8_I(M_I[8]),
  .Msg9_I(M_I[9]),
  .Msg10_I(M_I[10]),
  .Msg11_I(M_I[11]),
  .Msg12_I(M_I[12]),
  .Msg13_I(M_I[13]),
  .Msg14_I(M_I[14]),
  .Msg15_I(M_I[15]),
  .Vld_O(vld),
  .H0_O(H_O[0]),
  .H1_O(H_O[1]),
  .H2_O(H_O[2]),
  .H3_O(H_O[3]),
  .H4_O(H_O[4]),
  .H5_O(H_O[5]),
  .H6_O(H_O[6]),
  .H7_O(H_O[7]) 
  );
  
  initial clk = 0;
  always #5 clk = ~clk;
  
  initial
  begin
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
    #50000;
    $display("End of simulation time is %d ",$time);
    $finish;
  end
  
endmodule : HashGenTB