// === G_function.v ===
module G_function(
  // Clock
  input  Clk,
  // Inputs
  input [31:0] A_I,
  input [31:0] B_I,
  input [31:0] C_I,
  input [31:0] D_I,
  input [31:0] X_I,
  input [31:0] Y_I,
  // Outputs to core
  output [31:0] A_O,
  output [31:0] B_O,
  output [31:0] C_O,
  output [31:0] D_O
  );
  
  reg [31:0] A0, A1, A2, A3 = 0;
  reg [31:0] B0, B1, B2, B3 = 0;
  reg [31:0] C0, C1, C2, C3 = 0;
  reg [31:0] D0, D1, D2, D3 = 0;
  
  wire [31:0] Aw_0, Dw_0, Cw_0, Bw_0;
  wire [31:0] Aw_1, Dw_1, Cw_1, Bw_1;
  
  assign Aw_0 = A_I + B_I + X_I;
  assign Dw_0 = D_I ^ Aw_0;
  assign Cw_0 = C_I + D0;
  assign Bw_0 = B_I ^ Cw_0;
  
  assign Aw_1 = A1 + B1 + Y_I;
  assign Dw_1 = D1 + Aw_1;
  assign Cw_1 = C1 + D2;
  assign Bw_1 = B1 ^ Cw_1; 
  
  
  
  always@(posedge Clk)
  begin : mix_process
    //1st part
    A0 <= Aw_0;
    // >>> 16
    D0 <= {Dw_0[15:0], Dw_0[31:16]};
    C0 <= Cw_0;
    // >>> 12
    B0 <= {Bw_0[11:0], Bw_0[31:12]};
    // Buffering
    A1 <= A0;
    B1 <= B0;
    D1 <= D0;
    C1 <= C0;
    
    //2nd part
    A2 <= Aw_1;
    D2 <= {Dw_1[7:0], Dw_1[31:8]};
    C2 <= Cw_1;
    B2 <= {Bw_1[6:0], Bw_1[31:7]};
    
    //Output buffer
    A3 <= A2;
    D3 <= D2;
    C3 <= C2;
    B3 <= B2;
    
  end
  
  assign A_O = A3;
  assign D_O = D3;
  assign C_O = C3;
  assign B_O = B3;
  
  
endmodule
  
  
  
  
  