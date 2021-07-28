// === HashGen.sv ===

`include "defines.sv"

module HashGen
  #(parameter ROUND_NUM = 7)
  (
  // Clock
  input  Clk,
  // Inputs
  input Strt_I,
  // block length in bytes
  input [31:0] BL_I,
  // chunk start
  input CS_flg_I,
  // chunk end
  input CE_flg_I,
  input ROOT_flg_I,
  input [7:0] [31:0] H_I,
  input [31:0] Msg0_I,
  input [31:0] Msg1_I,
  input [31:0] Msg2_I,
  input [31:0] Msg3_I,
  input [31:0] Msg4_I,
  input [31:0] Msg5_I,
  input [31:0] Msg6_I,
  input [31:0] Msg7_I,
  input [31:0] Msg8_I,
  input [31:0] Msg9_I,
  input [31:0] Msg10_I,
  input [31:0] Msg11_I,
  input [31:0] Msg12_I,
  input [31:0] Msg13_I,
  input [31:0] Msg14_I,
  input [31:0] Msg15_I,
  
  // Outputs
  output Vld_O,
  
  // Outputs
  output [31:0] H0_O,
  output [31:0] H1_O,
  output [31:0] H2_O,
  output [31:0] H3_O,
  output [31:0] H4_O,
  output [31:0] H5_O,
  output [31:0] H6_O,
  output [31:0] H7_O
  );
  
  localparam logic[31:0] IV [0:7] = {
    `IV_0, `IV_1, `IV_2, `IV_3,
    `IV_4, `IV_5, `IV_6, `IV_7
  };
  
  localparam integer perm_num [0:15] = {
    2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8
  };
  
  localparam shortint ROUND_DELAY = 11;
  localparam shortint HASH_DELAY = (ROUND_NUM*ROUND_DELAY + 3);
  
  
  logic [15:0][ROUND_NUM-1:0][31:0] MsgArray;
  logic [15:0][ROUND_NUM:0][31:0] VArray;
  
  
  // set of domain separation bit flags
  logic parent = 0;
  logic keyed_hash = 0;
  logic derive_key_context = 0;
  logic derive_key_material = 0;
  
  logic vld_reg = 0;
  logic strt_flg = 0;
  
  shortint cntr_reg = 0;
  
  
  logic [15:0][31:0] hv;
  
  genvar k;
  // input chaining value h0-h7
  generate  
    for (k = 0; k < 8; k = k + 1)
    begin : chaining_value
      assign VArray[k][0] = H_I[k];
    end
  endgenerate

  
  //IV 0-3
  assign VArray[8][0] = IV[0];
  assign VArray[9][0] = IV[1];
  assign VArray[10][0] = IV[2];
  assign VArray[11][0] = IV[3];
  
  // counter
  assign VArray[12][0] = 0;
  // countershift
  assign VArray[13][0] = 0;
  // block length
  assign VArray[14][0] = BL_I;
  // flags
  assign VArray[15][0][31:7] = 0;
  assign VArray[15][0][6:0] = {
    derive_key_material,
    derive_key_context,
    keyed_hash, ROOT_flg_I, parent,
    CE_flg_I, CS_flg_I
  };
  
  // message assigning
  assign MsgArray[0][0] = Msg0_I;
  assign MsgArray[1][0] = Msg1_I;
  assign MsgArray[2][0] = Msg2_I;
  assign MsgArray[3][0] = Msg3_I;
  assign MsgArray[4][0] = Msg4_I;
  assign MsgArray[5][0] = Msg5_I;
  assign MsgArray[6][0] = Msg6_I;
  assign MsgArray[7][0] = Msg7_I;
  assign MsgArray[8][0] = Msg8_I;
  assign MsgArray[9][0] = Msg9_I;
  assign MsgArray[10][0] = Msg10_I;
  assign MsgArray[11][0] = Msg11_I;
  assign MsgArray[12][0] = Msg12_I;
  assign MsgArray[13][0] = Msg13_I;
  assign MsgArray[14][0] = Msg14_I;
  assign MsgArray[15][0] = Msg15_I;
  
  // delay of the valid signal
  always@(posedge Clk) 
  begin : delay_counter
    if(Strt_I) begin
      cntr_reg <= 0;
      strt_flg <= 1'b1;
    end
    else if(cntr_reg < HASH_DELAY)
      cntr_reg++;
    else
      cntr_reg <= cntr_reg;
  end
  
  // valid register
  always@(posedge Clk) 
  begin : valid_process
    vld_reg <= ((cntr_reg == HASH_DELAY) && strt_flg);
  end
  
  assign Vld_O = vld_reg;
  
  
  genvar i;
  genvar j;
  
  generate  
    for (i = 1; i < (ROUND_NUM + 1); i = i + 1)
    begin : hasher
    
      
      for (j = 0; j < 16; j = j + 1)
      begin
        always@(posedge Clk)
        begin : message_permutation
          MsgArray[j][i] <= MsgArray[perm_num[j]][i-1];
        end
      end
      
      G_round G_round_i(
      .Clk(Clk),
      .V0_I(VArray[0][i-1]),
      .V1_I(VArray[1][i-1]),
      .V2_I(VArray[2][i-1]),
      .V3_I(VArray[3][i-1]),
      .V4_I(VArray[4][i-1]),
      .V5_I(VArray[5][i-1]),
      .V6_I(VArray[6][i-1]),
      .V7_I(VArray[7][i-1]),
      .V8_I(VArray[8][i-1]),
      .V9_I(VArray[9][i-1]),
      .V10_I(VArray[10][i-1]),
      .V11_I(VArray[11][i-1]),
      .V12_I(VArray[12][i-1]),
      .V13_I(VArray[13][i-1]),
      .V14_I(VArray[14][i-1]),
      .V15_I(VArray[15][i-1]),
      .M0_I(MsgArray[0][i-1]),
      .M1_I(MsgArray[1][i-1]),
      .M2_I(MsgArray[2][i-1]),
      .M3_I(MsgArray[3][i-1]),
      .M4_I(MsgArray[4][i-1]),
      .M5_I(MsgArray[5][i-1]),
      .M6_I(MsgArray[6][i-1]),
      .M7_I(MsgArray[7][i-1]),
      .M8_I(MsgArray[8][i-1]),
      .M9_I(MsgArray[9][i-1]),
      .M10_I(MsgArray[10][i-1]),
      .M11_I(MsgArray[11][i-1]),
      .M12_I(MsgArray[12][i-1]),
      .M13_I(MsgArray[13][i-1]),
      .M14_I(MsgArray[14][i-1]),
      .M15_I(MsgArray[15][i-1]),
      .V0_O(VArray[0][i]),
      .V1_O(VArray[1][i]),
      .V2_O(VArray[2][i]),
      .V3_O(VArray[3][i]),
      .V4_O(VArray[4][i]),
      .V5_O(VArray[5][i]),
      .V6_O(VArray[6][i]),
      .V7_O(VArray[7][i]),
      .V8_O(VArray[8][i]),
      .V9_O(VArray[9][i]),
      .V10_O(VArray[10][i]),
      .V11_O(VArray[11][i]),
      .V12_O(VArray[12][i]),
      .V13_O(VArray[13][i]),
      .V14_O(VArray[14][i]),
      .V15_O(VArray[15][i])  
      );
    end      
  endgenerate
  
  // compression function
  always@(posedge Clk) 
  begin : compress
    for(int l = 0; l < 8; l++) begin
      hv[l] <= VArray[l][ROUND_NUM] ^ VArray[l+8][ROUND_NUM];
      // chaining values
      hv[l+8] <= VArray[l+8][ROUND_NUM] ^ hv[l];
    end
  end
  
  assign H0_O = hv[0];
  assign H1_O = hv[1];
  assign H2_O = hv[2];
  assign H3_O = hv[3];
  assign H4_O = hv[4];
  assign H5_O = hv[5];
  assign H6_O = hv[6];
  assign H7_O = hv[7];
  
endmodule