// === G_round.v ===
module G_round(
  // Clock
  input  Clk,
  // Inputs
  input [31:0] V0_I,
  input [31:0] V1_I,
  input [31:0] V2_I,
  input [31:0] V3_I,
  input [31:0] V4_I,
  input [31:0] V5_I,
  input [31:0] V6_I,
  input [31:0] V7_I,
  input [31:0] V8_I,
  input [31:0] V9_I,
  input [31:0] V10_I,
  input [31:0] V11_I,
  input [31:0] V12_I,
  input [31:0] V13_I,
  input [31:0] V14_I,
  input [31:0] V15_I,
  input [31:0] M0_I,
  input [31:0] M1_I,
  input [31:0] M2_I,
  input [31:0] M3_I,
  input [31:0] M4_I,
  input [31:0] M5_I,
  input [31:0] M6_I,
  input [31:0] M7_I,
  input [31:0] M8_I,
  input [31:0] M9_I,
  input [31:0] M10_I,
  input [31:0] M11_I,
  input [31:0] M12_I,
  input [31:0] M13_I,
  input [31:0] M14_I,
  input [31:0] M15_I,
  // Outputs
  output [31:0] V0_O,
  output [31:0] V1_O,
  output [31:0] V2_O,
  output [31:0] V3_O,
  output [31:0] V4_O,
  output [31:0] V5_O,
  output [31:0] V6_O,
  output [31:0] V7_O,
  output [31:0] V8_O,
  output [31:0] V9_O,
  output [31:0] V10_O,
  output [31:0] V11_O,
  output [31:0] V12_O,
  output [31:0] V13_O,
  output [31:0] V14_O,
  output [31:0] V15_O
  
  );
  
  wire [31:0] Vw [0:15];
  
  
  QuadG QuadG_column(
  .Clk(Clk),
  .A_I({V3_I, V2_I, V1_I, V0_I}),
  .B_I({V7_I, V6_I, V5_I, V4_I}),
  .C_I({V11_I, V10_I, V9_I, V8_I}),
  .D_I({V15_I, V14_I, V13_I, V12_I}),
  .X_I({M6_I,M4_I,M2_I,M0_I}),
  .Y_I({M7_I,M5_I,M3_I,M1_I}),
  .A_O({Vw[3],Vw[2],Vw[1],Vw[0]}),
  .B_O({Vw[7],Vw[6],Vw[5],Vw[4]}),
  .C_O({Vw[11],Vw[10],Vw[9],Vw[8]}),
  .D_O({Vw[15],Vw[14],Vw[13],Vw[12]})
  );
  
  QuadG QuadG_diagonal(
  .Clk(Clk),
  .A_I({Vw[15],Vw[10],Vw[5],Vw[0]}),
  .B_I({Vw[12],Vw[11],Vw[6],Vw[1]}),
  .C_I({Vw[13],Vw[8],Vw[7],Vw[2]}),
  .D_I({Vw[14],Vw[9],Vw[4],Vw[3]}),
  .X_I({M14_I,M12_I,M10_I,M8_I}),
  .Y_I({M15_I,M13_I,M11_I,M9_I}),
  .A_O({V15_O, V10_O, V5_O, V0_O}),
  .B_O({V12_O, V11_O, V6_O, V1_O}),
  .C_O({V13_O, V8_O, V7_O, V2_O}),
  .D_O({V14_O, V9_O, V4_O, V3_O})
  );
  
endmodule