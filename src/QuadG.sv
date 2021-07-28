// === QuadG.v ===
module QuadG
  #(parameter WIDTH = 4*32)
  (
  // Clock
  input  Clk,
  // Inputs
  input [WIDTH-1:0] A_I,
  input [WIDTH-1:0] B_I,
  input [WIDTH-1:0] C_I,
  input [WIDTH-1:0] D_I,
  input [WIDTH-1:0] X_I,
  input [WIDTH-1:0] Y_I,
  // Outputs to core
  output [WIDTH-1:0] A_O,
  output [WIDTH-1:0] B_O,
  output [WIDTH-1:0] C_O,
  output [WIDTH-1:0] D_O
  );
  
  wire [31:0] Aw, Bw, Cw, Dw [0:3];
  
  genvar i;
  
  generate  
    for (i = 0; i < 4; i = i + 1)
    begin : quad
      G_function G_function_i(
        .Clk(Clk),
        .A_I(A_I[(i+1)*32-1 -: 32]),
        .B_I(B_I[(i+1)*32-1 -: 32]),
        .C_I(C_I[(i+1)*32-1 -: 32]),
        .D_I(D_I[(i+1)*32-1 -: 32]),
        .X_I(X_I[(i+1)*32-1 -: 32]),
        .Y_I(Y_I[(i+1)*32-1 -: 32]),
        .A_O(Aw[i]),
        .B_O(Bw[i]),
        .C_O(Cw[i]),
        .D_O(Dw[i])  
      );
      assign A_O[(i+1)*32-1 -: 32] = Aw[i];
      assign B_O[(i+1)*32-1 -: 32] = Bw[i];
      assign C_O[(i+1)*32-1 -: 32] = Cw[i];
      assign D_O[(i+1)*32-1 -: 32] = Dw[i];
    end      
  endgenerate
  
endmodule