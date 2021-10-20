// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2021.1 (64-bit)
// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// ==============================================================
`timescale 1ns/1ps
module AlephMiner_control_s_axi
#(parameter
    C_S_AXI_ADDR_WIDTH = 7,
    C_S_AXI_DATA_WIDTH = 32
)(
    input  wire                          ACLK,
    input  wire                          ARESET,
    input  wire                          ACLK_EN,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] AWADDR,
    input  wire                          AWVALID,
    output wire                          AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1:0] WDATA,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0] WSTRB,
    input  wire                          WVALID,
    output wire                          WREADY,
    output wire [1:0]                    BRESP,
    output wire                          BVALID,
    input  wire                          BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] ARADDR,
    input  wire                          ARVALID,
    output wire                          ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1:0] RDATA,
    output wire [1:0]                    RRESP,
    output wire                          RVALID,
    input  wire                          RREADY,
    output wire                          interrupt,
    output wire [7:0]                    FromGroup,
    output wire [7:0]                    ToGroup,
    output wire [7:0]                    Groups,
    output wire [7:0]                    GroupsShifter,
    output wire [7:0]                    ChainNum,
    output wire [15:0]                   ChunkLength,
    output wire [63:0]                   TargetIn,
    output wire [63:0]                   HeaderBlobIn,
    output wire [63:0]                   Nonce,
    output wire [63:0]                   HashCounterOut,
    output wire [63:0]                   HashOut,
    output wire                          ap_start,
    input  wire                          ap_done,
    input  wire                          ap_ready,
    input  wire                          ap_idle
);
//------------------------Address Info-------------------
// 0x00 : Control signals
//        bit 0  - ap_start (Read/Write/COH)
//        bit 1  - ap_done (Read/COR)
//        bit 2  - ap_idle (Read)
//        bit 3  - ap_ready (Read/COR)
//        bit 7  - auto_restart (Read/Write)
//        others - reserved
// 0x04 : Global Interrupt Enable Register
//        bit 0  - Global Interrupt Enable (Read/Write)
//        others - reserved
// 0x08 : IP Interrupt Enable Register (Read/Write)
//        bit 0  - enable ap_done interrupt (Read/Write)
//        bit 1  - enable ap_ready interrupt (Read/Write)
//        others - reserved
// 0x0c : IP Interrupt Status Register (Read/TOW)
//        bit 0  - ap_done (COR/TOW)
//        bit 1  - ap_ready (COR/TOW)
//        others - reserved
// 0x10 : Data signal of FromGroup
//        bit 7~0 - FromGroup[7:0] (Read/Write)
//        others  - reserved
// 0x14 : reserved
// 0x18 : Data signal of ToGroup
//        bit 7~0 - ToGroup[7:0] (Read/Write)
//        others  - reserved
// 0x1c : reserved
// 0x20 : Data signal of Groups
//        bit 7~0 - Groups[7:0] (Read/Write)
//        others  - reserved
// 0x24 : reserved
// 0x28 : Data signal of GroupsShifter
//        bit 7~0 - GroupsShifter[7:0] (Read/Write)
//        others  - reserved
// 0x2c : reserved
// 0x30 : Data signal of ChainNum
//        bit 7~0 - ChainNum[7:0] (Read/Write)
//        others  - reserved
// 0x34 : reserved
// 0x38 : Data signal of ChunkLength
//        bit 15~0 - ChunkLength[15:0] (Read/Write)
//        others   - reserved
// 0x3c : reserved
// 0x40 : Data signal of TargetIn
//        bit 31~0 - TargetIn[31:0] (Read/Write)
// 0x44 : Data signal of TargetIn
//        bit 31~0 - TargetIn[63:32] (Read/Write)
// 0x48 : reserved
// 0x4c : Data signal of HeaderBlobIn
//        bit 31~0 - HeaderBlobIn[31:0] (Read/Write)
// 0x50 : Data signal of HeaderBlobIn
//        bit 31~0 - HeaderBlobIn[63:32] (Read/Write)
// 0x54 : reserved
// 0x58 : Data signal of Nonce
//        bit 31~0 - Nonce[31:0] (Read/Write)
// 0x5c : Data signal of Nonce
//        bit 31~0 - Nonce[63:32] (Read/Write)
// 0x60 : reserved
// 0x64 : Data signal of HashCounterOut
//        bit 31~0 - HashCounterOut[31:0] (Read/Write)
// 0x68 : Data signal of HashCounterOut
//        bit 31~0 - HashCounterOut[63:32] (Read/Write)
// 0x6c : reserved
// 0x70 : Data signal of HashOut
//        bit 31~0 - HashOut[31:0] (Read/Write)
// 0x74 : Data signal of HashOut
//        bit 31~0 - HashOut[63:32] (Read/Write)
// 0x78 : reserved
// (SC = Self Clear, COR = Clear on Read, TOW = Toggle on Write, COH = Clear on Handshake)

//------------------------Parameter----------------------
localparam
    ADDR_AP_CTRL               = 7'h00,
    ADDR_GIE                   = 7'h04,
    ADDR_IER                   = 7'h08,
    ADDR_ISR                   = 7'h0c,
    ADDR_FROMGROUP_DATA_0      = 7'h10,
    ADDR_FROMGROUP_CTRL        = 7'h14,
    ADDR_TOGROUP_DATA_0        = 7'h18,
    ADDR_TOGROUP_CTRL          = 7'h1c,
    ADDR_GROUPS_DATA_0         = 7'h20,
    ADDR_GROUPS_CTRL           = 7'h24,
    ADDR_GROUPSSHIFTER_DATA_0  = 7'h28,
    ADDR_GROUPSSHIFTER_CTRL    = 7'h2c,
    ADDR_CHAINNUM_DATA_0       = 7'h30,
    ADDR_CHAINNUM_CTRL         = 7'h34,
    ADDR_CHUNKLENGTH_DATA_0    = 7'h38,
    ADDR_CHUNKLENGTH_CTRL      = 7'h3c,
    ADDR_TARGETIN_DATA_0       = 7'h40,
    ADDR_TARGETIN_DATA_1       = 7'h44,
    ADDR_TARGETIN_CTRL         = 7'h48,
    ADDR_HEADERBLOBIN_DATA_0   = 7'h4c,
    ADDR_HEADERBLOBIN_DATA_1   = 7'h50,
    ADDR_HEADERBLOBIN_CTRL     = 7'h54,
    ADDR_NONCE_DATA_0          = 7'h58,
    ADDR_NONCE_DATA_1          = 7'h5c,
    ADDR_NONCE_CTRL            = 7'h60,
    ADDR_HASHCOUNTEROUT_DATA_0 = 7'h64,
    ADDR_HASHCOUNTEROUT_DATA_1 = 7'h68,
    ADDR_HASHCOUNTEROUT_CTRL   = 7'h6c,
    ADDR_HASHOUT_DATA_0        = 7'h70,
    ADDR_HASHOUT_DATA_1        = 7'h74,
    ADDR_HASHOUT_CTRL          = 7'h78,
    WRIDLE                     = 2'd0,
    WRDATA                     = 2'd1,
    WRRESP                     = 2'd2,
    WRRESET                    = 2'd3,
    RDIDLE                     = 2'd0,
    RDDATA                     = 2'd1,
    RDRESET                    = 2'd2,
    ADDR_BITS                = 7;

//------------------------Local signal-------------------
    reg  [1:0]                    wstate = WRRESET;
    reg  [1:0]                    wnext;
    reg  [ADDR_BITS-1:0]          waddr;
    wire [C_S_AXI_DATA_WIDTH-1:0] wmask;
    wire                          aw_hs;
    wire                          w_hs;
    reg  [1:0]                    rstate = RDRESET;
    reg  [1:0]                    rnext;
    reg  [C_S_AXI_DATA_WIDTH-1:0] rdata;
    wire                          ar_hs;
    wire [ADDR_BITS-1:0]          raddr;
    // internal registers
    reg                           int_ap_idle;
    reg                           int_ap_ready = 1'b0;
    wire                          task_ap_ready;
    reg                           int_ap_done = 1'b0;
    wire                          task_ap_done;
    reg                           int_task_ap_done = 1'b0;
    reg                           int_ap_start = 1'b0;
    reg                           int_auto_restart = 1'b0;
    reg                           auto_restart_status = 1'b0;
    wire                          auto_restart_done;
    reg                           int_gie = 1'b0;
    reg  [1:0]                    int_ier = 2'b0;
    reg  [1:0]                    int_isr = 2'b0;
    reg  [7:0]                    int_FromGroup = 'b0;
    reg  [7:0]                    int_ToGroup = 'b0;
    reg  [7:0]                    int_Groups = 'b0;
    reg  [7:0]                    int_GroupsShifter = 'b0;
    reg  [7:0]                    int_ChainNum = 'b0;
    reg  [15:0]                   int_ChunkLength = 'b0;
    reg  [63:0]                   int_TargetIn = 'b0;
    reg  [63:0]                   int_HeaderBlobIn = 'b0;
    reg  [63:0]                   int_Nonce = 'b0;
    reg  [63:0]                   int_HashCounterOut = 'b0;
    reg  [63:0]                   int_HashOut = 'b0;

//------------------------Instantiation------------------


//------------------------AXI write fsm------------------
assign AWREADY = (wstate == WRIDLE);
assign WREADY  = (wstate == WRDATA);
assign BRESP   = 2'b00;  // OKAY
assign BVALID  = (wstate == WRRESP);
assign wmask   = { {8{WSTRB[3]}}, {8{WSTRB[2]}}, {8{WSTRB[1]}}, {8{WSTRB[0]}} };
assign aw_hs   = AWVALID & AWREADY;
assign w_hs    = WVALID & WREADY;

// wstate
always @(posedge ACLK) begin
    if (ARESET)
        wstate <= WRRESET;
    else if (ACLK_EN)
        wstate <= wnext;
end

// wnext
always @(*) begin
    case (wstate)
        WRIDLE:
            if (AWVALID)
                wnext = WRDATA;
            else
                wnext = WRIDLE;
        WRDATA:
            if (WVALID)
                wnext = WRRESP;
            else
                wnext = WRDATA;
        WRRESP:
            if (BREADY)
                wnext = WRIDLE;
            else
                wnext = WRRESP;
        default:
            wnext = WRIDLE;
    endcase
end

// waddr
always @(posedge ACLK) begin
    if (ACLK_EN) begin
        if (aw_hs)
            waddr <= AWADDR[ADDR_BITS-1:0];
    end
end

//------------------------AXI read fsm-------------------
assign ARREADY = (rstate == RDIDLE);
assign RDATA   = rdata;
assign RRESP   = 2'b00;  // OKAY
assign RVALID  = (rstate == RDDATA);
assign ar_hs   = ARVALID & ARREADY;
assign raddr   = ARADDR[ADDR_BITS-1:0];

// rstate
always @(posedge ACLK) begin
    if (ARESET)
        rstate <= RDRESET;
    else if (ACLK_EN)
        rstate <= rnext;
end

// rnext
always @(*) begin
    case (rstate)
        RDIDLE:
            if (ARVALID)
                rnext = RDDATA;
            else
                rnext = RDIDLE;
        RDDATA:
            if (RREADY & RVALID)
                rnext = RDIDLE;
            else
                rnext = RDDATA;
        default:
            rnext = RDIDLE;
    endcase
end

// rdata
always @(posedge ACLK) begin
    if (ACLK_EN) begin
        if (ar_hs) begin
            rdata <= 'b0;
            case (raddr)
                ADDR_AP_CTRL: begin
                    rdata[0] <= int_ap_start;
                    rdata[1] <= int_task_ap_done;
                    rdata[2] <= int_ap_idle;
                    rdata[3] <= int_ap_ready;
                    rdata[7] <= int_auto_restart;
                end
                ADDR_GIE: begin
                    rdata <= int_gie;
                end
                ADDR_IER: begin
                    rdata <= int_ier;
                end
                ADDR_ISR: begin
                    rdata <= int_isr;
                end
                ADDR_FROMGROUP_DATA_0: begin
                    rdata <= int_FromGroup[7:0];
                end
                ADDR_TOGROUP_DATA_0: begin
                    rdata <= int_ToGroup[7:0];
                end
                ADDR_GROUPS_DATA_0: begin
                    rdata <= int_Groups[7:0];
                end
                ADDR_GROUPSSHIFTER_DATA_0: begin
                    rdata <= int_GroupsShifter[7:0];
                end
                ADDR_CHAINNUM_DATA_0: begin
                    rdata <= int_ChainNum[7:0];
                end
                ADDR_CHUNKLENGTH_DATA_0: begin
                    rdata <= int_ChunkLength[15:0];
                end
                ADDR_TARGETIN_DATA_0: begin
                    rdata <= int_TargetIn[31:0];
                end
                ADDR_TARGETIN_DATA_1: begin
                    rdata <= int_TargetIn[63:32];
                end
                ADDR_HEADERBLOBIN_DATA_0: begin
                    rdata <= int_HeaderBlobIn[31:0];
                end
                ADDR_HEADERBLOBIN_DATA_1: begin
                    rdata <= int_HeaderBlobIn[63:32];
                end
                ADDR_NONCE_DATA_0: begin
                    rdata <= int_Nonce[31:0];
                end
                ADDR_NONCE_DATA_1: begin
                    rdata <= int_Nonce[63:32];
                end
                ADDR_HASHCOUNTEROUT_DATA_0: begin
                    rdata <= int_HashCounterOut[31:0];
                end
                ADDR_HASHCOUNTEROUT_DATA_1: begin
                    rdata <= int_HashCounterOut[63:32];
                end
                ADDR_HASHOUT_DATA_0: begin
                    rdata <= int_HashOut[31:0];
                end
                ADDR_HASHOUT_DATA_1: begin
                    rdata <= int_HashOut[63:32];
                end
            endcase
        end
    end
end


//------------------------Register logic-----------------
assign interrupt         = int_gie & (|int_isr);
assign ap_start          = int_ap_start;
assign task_ap_done      = (ap_done && !auto_restart_status) || auto_restart_done;
assign task_ap_ready     = ap_ready && !int_auto_restart;
assign auto_restart_done = auto_restart_status && (ap_idle && !int_ap_idle);
assign FromGroup         = int_FromGroup;
assign ToGroup           = int_ToGroup;
assign Groups            = int_Groups;
assign GroupsShifter     = int_GroupsShifter;
assign ChainNum          = int_ChainNum;
assign ChunkLength       = int_ChunkLength;
assign TargetIn          = int_TargetIn;
assign HeaderBlobIn      = int_HeaderBlobIn;
assign Nonce             = int_Nonce;
assign HashCounterOut    = int_HashCounterOut;
assign HashOut           = int_HashOut;
// int_ap_start
always @(posedge ACLK) begin
    if (ARESET)
        int_ap_start <= 1'b0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AP_CTRL && WSTRB[0] && WDATA[0])
            int_ap_start <= 1'b1;
        else if (ap_ready)
            int_ap_start <= int_auto_restart; // clear on handshake/auto restart
    end
end

// int_ap_done
always @(posedge ACLK) begin
    if (ARESET)
        int_ap_done <= 1'b0;
    else if (ACLK_EN) begin
            int_ap_done <= ap_done;
    end
end

// int_task_ap_done
always @(posedge ACLK) begin
    if (ARESET)
        int_task_ap_done <= 1'b0;
    else if (ACLK_EN) begin
        if (task_ap_done)
            int_task_ap_done <= 1'b1;
        else if (ar_hs && raddr == ADDR_AP_CTRL)
            int_task_ap_done <= 1'b0; // clear on read
    end
end

// int_ap_idle
always @(posedge ACLK) begin
    if (ARESET)
        int_ap_idle <= 1'b0;
    else if (ACLK_EN) begin
            int_ap_idle <= ap_idle;
    end
end

// int_ap_ready
always @(posedge ACLK) begin
    if (ARESET)
        int_ap_ready <= 1'b0;
    else if (ACLK_EN) begin
        if (task_ap_ready)
            int_ap_ready <= 1'b1;
        else if (ar_hs && raddr == ADDR_AP_CTRL)
            int_ap_ready <= 1'b0;
    end
end

// int_auto_restart
always @(posedge ACLK) begin
    if (ARESET)
        int_auto_restart <= 1'b0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AP_CTRL && WSTRB[0])
            int_auto_restart <=  WDATA[7];
    end
end

// auto_restart_status
always @(posedge ACLK) begin
    if (ARESET)
        auto_restart_status <= 1'b0;
    else if (ACLK_EN) begin
        if (int_auto_restart)
            auto_restart_status <= 1'b1;
        else if (ap_idle)
            auto_restart_status <= 1'b0;
    end
end

// int_gie
always @(posedge ACLK) begin
    if (ARESET)
        int_gie <= 1'b0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_GIE && WSTRB[0])
            int_gie <= WDATA[0];
    end
end

// int_ier
always @(posedge ACLK) begin
    if (ARESET)
        int_ier <= 1'b0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_IER && WSTRB[0])
            int_ier <= WDATA[1:0];
    end
end

// int_isr[0]
always @(posedge ACLK) begin
    if (ARESET)
        int_isr[0] <= 1'b0;
    else if (ACLK_EN) begin
        if (int_ier[0] & ap_done)
            int_isr[0] <= 1'b1;
        else if (w_hs && waddr == ADDR_ISR && WSTRB[0])
            int_isr[0] <= int_isr[0] ^ WDATA[0]; // toggle on write
    end
end

// int_isr[1]
always @(posedge ACLK) begin
    if (ARESET)
        int_isr[1] <= 1'b0;
    else if (ACLK_EN) begin
        if (int_ier[1] & ap_ready)
            int_isr[1] <= 1'b1;
        else if (w_hs && waddr == ADDR_ISR && WSTRB[0])
            int_isr[1] <= int_isr[1] ^ WDATA[1]; // toggle on write
    end
end

// int_FromGroup[7:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_FromGroup[7:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_FROMGROUP_DATA_0)
            int_FromGroup[7:0] <= (WDATA[31:0] & wmask) | (int_FromGroup[7:0] & ~wmask);
    end
end

// int_ToGroup[7:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_ToGroup[7:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_TOGROUP_DATA_0)
            int_ToGroup[7:0] <= (WDATA[31:0] & wmask) | (int_ToGroup[7:0] & ~wmask);
    end
end

// int_Groups[7:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_Groups[7:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_GROUPS_DATA_0)
            int_Groups[7:0] <= (WDATA[31:0] & wmask) | (int_Groups[7:0] & ~wmask);
    end
end

// int_GroupsShifter[7:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_GroupsShifter[7:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_GROUPSSHIFTER_DATA_0)
            int_GroupsShifter[7:0] <= (WDATA[31:0] & wmask) | (int_GroupsShifter[7:0] & ~wmask);
    end
end

// int_ChainNum[7:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_ChainNum[7:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_CHAINNUM_DATA_0)
            int_ChainNum[7:0] <= (WDATA[31:0] & wmask) | (int_ChainNum[7:0] & ~wmask);
    end
end

// int_ChunkLength[15:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_ChunkLength[15:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_CHUNKLENGTH_DATA_0)
            int_ChunkLength[15:0] <= (WDATA[31:0] & wmask) | (int_ChunkLength[15:0] & ~wmask);
    end
end

// int_TargetIn[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_TargetIn[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_TARGETIN_DATA_0)
            int_TargetIn[31:0] <= (WDATA[31:0] & wmask) | (int_TargetIn[31:0] & ~wmask);
    end
end

// int_TargetIn[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_TargetIn[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_TARGETIN_DATA_1)
            int_TargetIn[63:32] <= (WDATA[31:0] & wmask) | (int_TargetIn[63:32] & ~wmask);
    end
end

// int_HeaderBlobIn[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_HeaderBlobIn[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_HEADERBLOBIN_DATA_0)
            int_HeaderBlobIn[31:0] <= (WDATA[31:0] & wmask) | (int_HeaderBlobIn[31:0] & ~wmask);
    end
end

// int_HeaderBlobIn[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_HeaderBlobIn[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_HEADERBLOBIN_DATA_1)
            int_HeaderBlobIn[63:32] <= (WDATA[31:0] & wmask) | (int_HeaderBlobIn[63:32] & ~wmask);
    end
end

// int_Nonce[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_Nonce[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_NONCE_DATA_0)
            int_Nonce[31:0] <= (WDATA[31:0] & wmask) | (int_Nonce[31:0] & ~wmask);
    end
end

// int_Nonce[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_Nonce[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_NONCE_DATA_1)
            int_Nonce[63:32] <= (WDATA[31:0] & wmask) | (int_Nonce[63:32] & ~wmask);
    end
end

// int_HashCounterOut[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_HashCounterOut[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_HASHCOUNTEROUT_DATA_0)
            int_HashCounterOut[31:0] <= (WDATA[31:0] & wmask) | (int_HashCounterOut[31:0] & ~wmask);
    end
end

// int_HashCounterOut[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_HashCounterOut[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_HASHCOUNTEROUT_DATA_1)
            int_HashCounterOut[63:32] <= (WDATA[31:0] & wmask) | (int_HashCounterOut[63:32] & ~wmask);
    end
end

// int_HashOut[31:0]
always @(posedge ACLK) begin
    if (ARESET)
        int_HashOut[31:0] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_HASHOUT_DATA_0)
            int_HashOut[31:0] <= (WDATA[31:0] & wmask) | (int_HashOut[31:0] & ~wmask);
    end
end

// int_HashOut[63:32]
always @(posedge ACLK) begin
    if (ARESET)
        int_HashOut[63:32] <= 0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_HASHOUT_DATA_1)
            int_HashOut[63:32] <= (WDATA[31:0] & wmask) | (int_HashOut[63:32] & ~wmask);
    end
end


//------------------------Memory logic-------------------

endmodule
