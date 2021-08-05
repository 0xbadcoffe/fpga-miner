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
  
  
  
  always@(posedge Clk)
  begin : mix_process
    reg [31:0] Av_0, Dv_0, Cv_0, Bv_0;
    reg [31:0] Av_1, Dv_1, Cv_1, Bv_1;
    //1st part
    Av_0 = A_I + B_I + X_I;
    A0 <= Av_0;
    Dv_0 = D_I ^ Av_0;
    // >>> 16
    D0 <= {Dv_0[15:0], Dv_0[31:16]};
    Cv_0 = C_I + D0;
    C0 <= Cv_0;
    
    Bv_0 = B_I ^ Cv_0;
    // >>> 12
    B0 <= {Bv_0[11:0], Bv_0[31:12]};
    // Buffering
    A1 <= A0;
    B1 <= B0;
    D1 <= D0;
    C1 <= C0;
    
    //2nd part
    Av_1 = A1 + B1 + Y_I;
    A2 <= Av_1;
    Dv_1 = D1 ^ Av_1;
    D2 <= {Dv_1[7:0], Dv_1[31:8]};
    Cv_1 = C1 + D2;
    C2 <= Cv_1;
    Bv_1 = B1 ^ Cv_1; 
    B2 <= {Bv_1[6:0], Bv_1[31:7]};
    
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
  
  
  
  
  