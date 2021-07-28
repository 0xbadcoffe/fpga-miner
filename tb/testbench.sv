module testbench;  

  logic clk;
  
  logic [31:0] V_I [0:15];
  logic [31:0] M_I [0:15];
  logic [31:0] V_O [0:15];
  
  // input chaining value h0-h7
  genvar i;
  generate
    for (i = 0; i < 8; i = i + 1)
    begin
      assign V_I[i] = i;
    end
  endgenerate
  
  
  //IV 0-3
  assign V_I[8] = 32'h6A09E667;
  assign V_I[9] = 32'hBB67AE85;
  assign V_I[10] = 32'h3C6EF372;
  assign V_I[11] = 32'hA54FF53A;
    
  //IV 4-7
  //0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
  
  // counter
  assign V_I[12] = 0;
  // countershift
  assign V_I[13] = 0;
  // block length
  assign V_I[14] = 0;
  // flags
  assign V_I[15] = 0;
  
  // message block
  //m0-m15
  genvar j;
  generate
    for (j = 0; j < 16; j = j + 1)
    begin
      assign M_I[j] = j*32'h55;
    end
  endgenerate

  G_round DUT(
  .Clk(clk),
  .V0_I(V_I[0]),
  .V1_I(V_I[1]),
  .V2_I(V_I[2]),
  .V3_I(V_I[3]),
  .V4_I(V_I[4]),
  .V5_I(V_I[5]),
  .V6_I(V_I[6]),
  .V7_I(V_I[7]),
  .V8_I(V_I[8]),
  .V9_I(V_I[9]),
  .V10_I(V_I[10]),
  .V11_I(V_I[11]),
  .V12_I(V_I[12]),
  .V13_I(V_I[13]),
  .V14_I(V_I[14]),
  .V15_I(V_I[15]),
  .M0_I(M_I[0]),
  .M1_I(M_I[1]),
  .M2_I(M_I[2]),
  .M3_I(M_I[3]),
  .M4_I(M_I[4]),
  .M5_I(M_I[5]),
  .M6_I(M_I[6]),
  .M7_I(M_I[7]),
  .M8_I(M_I[8]),
  .M9_I(M_I[9]),
  .M10_I(M_I[10]),
  .M11_I(M_I[11]),
  .M12_I(M_I[12]),
  .M13_I(M_I[12]),
  .M14_I(M_I[14]),
  .M15_I(M_I[15]),
  .V0_O(V_O[0]),
  .V1_O(V_O[1]),
  .V2_O(V_O[2]),
  .V3_O(V_O[3]),
  .V4_O(V_O[4]),
  .V5_O(V_O[5]),
  .V6_O(V_O[6]),
  .V7_O(V_O[7]),
  .V8_O(V_O[8]),
  .V9_O(V_O[9]),
  .V10_O(V_O[10]),
  .V11_O(V_O[11]),
  .V12_O(V_O[12]),
  .V13_O(V_O[13]),
  .V14_O(V_O[14]),
  .V15_O(V_O[15])  
  );
  
  initial clk = 0;
  always #10 clk = ~clk;
  
  initial
  begin
    #50000;
    $display("End of simulation time is %d ",$time);
    $finish;
  end
  
endmodule : testbench