// === G_function.sv ===
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
  
  reg [31:0] A0, A1, A2 = 0;
  reg [31:0] B0, B1, B2 = 0;
  reg [31:0] C0, C1, C2 = 0;
  reg [31:0] D0, D1, D2 = 0;
  
  // shift registers for pipeline
  reg [2:0][31:0] Y_shr;
  reg [1:0][31:0] A_shr;
  reg [1:0][31:0] B_shr;
  reg [1:0][31:0] C_shr;
  reg [1:0][31:0] D_shr;
  
  always@(posedge Clk)
  begin : pipeline
    A_shr[0] <= A0;
    B_shr[0] <= B_I;
    C_shr[0] <= C_I;
    D_shr[0] <= D0;
    A_shr[1] <= A2;
    B_shr[1] <= B1;
    C_shr[1] <= C1;
    D_shr[1] <= D2;
    Y_shr[0] <= Y_I;
    Y_shr[2:1] <= Y_shr[1:0];
  end
  
  
  
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
    Cv_0 = C_shr[0] + D0;
    C0 <= Cv_0;
    
    Bv_0 = B_shr[0] ^ Cv_0;
    // >>> 12
    B0 <= {Bv_0[11:0], Bv_0[31:12]};
    // Buffering
    A1 <= A_shr[0];
    B1 <= B0;
    D1 <= D_shr[0];
    C1 <= C0;
    
    //2nd part
    Av_1 = A1 + B1 + Y_shr[2];
    A2 <= Av_1;
    Dv_1 = D1 ^ Av_1;
    D2 <= {Dv_1[7:0], Dv_1[31:8]};
    Cv_1 = C_shr[1] + D2;
    C2 <= Cv_1;
    Bv_1 = B_shr[1] ^ Cv_1; 
    B2 <= {Bv_1[6:0], Bv_1[31:7]};
    
    
  end
  
  assign A_O = A_shr[1];
  assign D_O = D_shr[1];
  assign C_O = C2;
  assign B_O = B2;
  
  
endmodule
  
  
  
  
  