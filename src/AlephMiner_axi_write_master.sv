// This is a generated file. Use and modify at your own risk.
////////////////////////////////////////////////////////////////////////////////

// Description: This is an AXI4 write master module example. The module
// demonstrates how to issue AXI write transactions to a memory mapped slave.
// Given a starting address offset and a transfer size in bytes, it will issue
// one or more AXI transactions by generating incrementing AXI write transfers
// when data is transfered over the AXI4-Stream interface.

// Theory of operation:
// It uses a minimum subset of the AXI4 protocol by omitting AXI4 signals that
// are not used.  When packaged as a kernel or IP, this allows for optimizations
// to occur within the AXI Interconnect system to increase Fmax, potentially
// increase performance, and reduce latency/area. When C_INCLUDE_DATA_FIFO is
// set to 1, a depth 32 FIFO is provided for extra buffering.
//
// When ctrl_start is asserted, the ctrl_addr_offset (assumed 4kb aligned) and
// the transfer size in bytes is registered into the module.  the The bulk of the
// logic consists of counters to track how many transfers/transactions have been
// issued.  When the transfer size is reached, and all transactions are
// committed, then done is asserted.
//
// Usage:
// 1) assign ctrl_addr_offset to a 4kB aligned starting address.
// 2) assign ctrl_xfer_size_in_bytes to the size in bytes of the requested transfer.
// 3) Assert ctrl_start for once cycle.  At the posedge, the ctrl_addr_offset and
// ctrl_xfer_size_in_bytes will be registered in the module, and will start
// to issue write address transfers when the first data arrives on the s_axis
// interface.  If the the transfer size is larger than 4096
// bytes, multiple transactions will be issued.
////////////////////////////////////////////////////////////////////////////////

// default_nettype of none prevents implicit wire declaration.
`default_nettype none

module AlephMiner_axi_write_master #(
  // Set to the address width of the interface
  parameter integer C_M_AXI_ADDR_WIDTH  = 64,

  // Set the data width of the interface
  // Range: 32, 64, 128, 256, 512, 1024
  parameter integer C_M_AXI_DATA_WIDTH  = 32,

  // Width of the ctrl_xfer_size_in_bytes input
  // Range: 16:C_M_AXI_ADDR_WIDTH
  parameter integer C_XFER_SIZE_WIDTH   = C_M_AXI_ADDR_WIDTH

)
(
  // AXI Interface
  input  wire                            aclk,
  input  wire                            areset,

  // Control signals
  input  wire                            ctrl_start,              // Pulse high for one cycle to begin reading
  output wire                            ctrl_done,               // Pulses high for one cycle when transfer request is complete
  // The following ctrl signals are sampled when ctrl_start is asserted
  input  wire [C_M_AXI_ADDR_WIDTH-1:0]   ctrl_addr_offset,        // Starting Address offset
  input  wire [C_XFER_SIZE_WIDTH-1:0]    ctrl_xfer_size_in_bytes, // Length in number of bytes, limited by the address width.

  // AXI4 master interface (write only)
  output wire                            m_axi_awvalid,
  input  wire                            m_axi_awready,
  output wire [C_M_AXI_ADDR_WIDTH-1:0]   m_axi_awaddr,
  output wire [7:0]                      m_axi_awlen,

  output wire                            m_axi_wvalid,
  input  wire                            m_axi_wready,
  output wire [C_M_AXI_DATA_WIDTH-1:0]   m_axi_wdata,
  output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
  output wire                            m_axi_wlast,

  input  wire                            m_axi_bvalid,
  output wire                            m_axi_bready,
  // AXI4-Stream interface
  input  wire                            Vld_I,
  output wire                            Rdy_O,
  input  wire  [C_M_AXI_DATA_WIDTH-1:0]  Data_I,
  output wire                            BVld_O

);

timeunit 1ps;
timeprecision 1ps;

///////////////////////////////////////////////////////////////////////////////
// functions
///////////////////////////////////////////////////////////////////////////////
function integer f_min (
  input integer a,
  input integer b
);
  f_min = (a < b) ? a : b;
endfunction

/////////////////////////////////////////////////////////////////////////////
// Local Parameters
/////////////////////////////////////////////////////////////////////////////
localparam integer LP_DW_BYTES                   = C_M_AXI_DATA_WIDTH/8;
localparam integer LP_LOG_DW_BYTES               = $clog2(LP_DW_BYTES);
localparam integer LP_MAX_BURST_LENGTH           = 256;   // Max AXI Protocol burst length
localparam integer LP_MAX_BURST_BYTES            = 4096;  // Max AXI Protocol burst size in bytes
localparam integer LP_AXI_BURST_LEN              = f_min(LP_MAX_BURST_BYTES/LP_DW_BYTES, LP_MAX_BURST_LENGTH);
localparam integer LP_LOG_BURST_LEN              = $clog2(LP_AXI_BURST_LEN);
localparam integer LP_LOG_MAX_W_TO_AW            = 8; // Allow up to 256 outstanding w to aw transactions
localparam integer LP_TOTAL_LEN_WIDTH            = C_XFER_SIZE_WIDTH-LP_LOG_DW_BYTES;
localparam [C_M_AXI_ADDR_WIDTH-1:0] LP_ADDR_MASK = LP_DW_BYTES*LP_AXI_BURST_LEN - 1;


/////////////////////////////////////////////////////////////////////////////
// Variables
/////////////////////////////////////////////////////////////////////////////
// Control
logic                                 done = 1'b0;
logic                                 has_partial_bursts;
logic                                 ctrl_start_d1 = 1'b0;
logic [C_M_AXI_ADDR_WIDTH-1:0]        addr_offset_r;
logic [LP_TOTAL_LEN_WIDTH-1:0]        total_len_r;
logic [LP_LOG_DW_BYTES   -1:0]        byte_remainder_r;
logic [LP_DW_BYTES   -1:0]            final_strb;
logic                                 start    = 1'b0;
logic                                 start_d1 = 1'b0;
logic [LP_LOG_BURST_LEN-1:0]          final_burst_len;
logic                                 single_transaction;
// Write data channel
logic                                 s_axis_tready_n;
logic                                 m_axi_wvalid_i;
logic                                 wxfer;       // Unregistered write data transfer
logic                                 wfirst = 1'b1;
logic                                 load_burst_cntr;
logic                                 w_final_transaction;
logic                                 w_final_transfer;
logic                                 w_almost_final_transaction = 1'b0;
logic                                 w_running = 1'b0;
// Write address channel
logic                                 awxfer;
logic                                 awvalid_r    = 1'b0;
logic [C_M_AXI_ADDR_WIDTH-1:0]        addr;
logic                                 wfirst_d1    = 1'b0;
logic                                 wfirst_pulse = 1'b0;
logic                                 idle_aw;
logic                                 aw_final_transaction;
// Write response channel
wire                                  bxfer;

logic [C_XFER_SIZE_WIDTH-1:0]  w_cntr;

/////////////////////////////////////////////////////////////////////////////
// Control logic
/////////////////////////////////////////////////////////////////////////////
assign ctrl_done = done;

// Count the number of transfers and assert done when the last m_axi_bvalid is received.
always @(posedge aclk) begin
  done <= bxfer;
end

always @(posedge aclk) begin
  ctrl_start_d1 <= ctrl_start;
end

always @(posedge aclk) begin
  if (ctrl_start) begin
    // Round transfer size up to integer value of the axi interface data width. Convert to axi_arlen format which is length -1.
    total_len_r <= ctrl_xfer_size_in_bytes[0+:LP_LOG_DW_BYTES] > 0
                      ? ctrl_xfer_size_in_bytes[LP_LOG_DW_BYTES+:LP_TOTAL_LEN_WIDTH]
                      : ctrl_xfer_size_in_bytes[LP_LOG_DW_BYTES+:LP_TOTAL_LEN_WIDTH] - 1'b1;
    // Align transfer to burst length to avoid AXI protocol issues if starting address is not correctly aligned.
    addr_offset_r <= ctrl_addr_offset & ~LP_ADDR_MASK;
    byte_remainder_r <= ctrl_xfer_size_in_bytes[0+:LP_LOG_DW_BYTES]-1'b1;
  end
end

// Determine how many full burst to issue and if there are any partial bursts.
assign has_partial_bursts = total_len_r[0+:LP_LOG_BURST_LEN] == '1 ? 1'b0 : 1'b1;

always @(posedge aclk) begin
  start <= ctrl_start_d1;
  final_burst_len  <= total_len_r[0+:LP_LOG_BURST_LEN];
end

// Special case if there is only 1 AXI transaction.
assign single_transaction = 1'b1;

/////////////////////////////////////////////////////////////////////////////
// AXI Write Data Channel
/////////////////////////////////////////////////////////////////////////////
// Used to gate valid/ready signals with running so transfers don't occur before the
// xfer size is known.
always @(posedge aclk) begin
  if (~areset) begin
    w_running <= 1'b0;
  end
  else begin
    w_running <= start            ? 1'b1 :
                 w_final_transfer ? 1'b0 :
                                    w_running ;
  end
end

  // Gate valid/ready signals with running so transfers don't occur before the
  // xfer size is known.
  assign m_axi_wvalid  = Vld_I & w_running & idle_aw;
  assign m_axi_wdata   = Data_I;
  assign Rdy_O = m_axi_wready & w_running & idle_aw;

assign wxfer = m_axi_wvalid & m_axi_wready;

assign w_final_transfer = m_axi_wlast & w_final_transaction & wxfer;
assign m_axi_wstrb   = m_axi_wlast & w_final_transaction ? final_strb : {(C_M_AXI_DATA_WIDTH/8){1'b1}};

always @(posedge aclk) begin
  final_strb[0] <= 1'b1;
  for (int i = 1; i < LP_DW_BYTES; i = i + 1) begin : loop
    final_strb[i] <= i > byte_remainder_r  ? 1'b0 : 1'b1;
  end
end

always @(posedge aclk) begin
  if (areset) begin
    wfirst <= 1'b1;
  end
  else begin
    wfirst <= wxfer ? m_axi_wlast : wfirst;
  end
end

// Load burst counter with partial burst if on final transaction or if there is only 1 transaction
assign load_burst_cntr = (start & single_transaction);

  always@(posedge aclk or negedge areset)
  begin : w_counter
    if(~areset)
      w_cntr <= 0;
    else if(load_burst_cntr)
      w_cntr <= 0;
    else if(wxfer)
      w_cntr <= w_cntr + 1;
  end

  assign m_axi_wlast = (w_cntr==final_burst_len);

  assign w_final_transaction = 1'b1;

/////////////////////////////////////////////////////////////////////////////
// AXI Write Address Channel
/////////////////////////////////////////////////////////////////////////////
// The address channel samples the data channel and send out transactions when
// first beat of m_axi_wdata is asserted. This ensures that address requests are not
// sent without data on the way.

assign m_axi_awvalid = awvalid_r;
assign awxfer = m_axi_awvalid & m_axi_awready;

always @(posedge aclk) begin
  if (~areset) begin
    awvalid_r <= 1'b0;
  end
  else begin
    awvalid_r <= ~idle_aw & ~awvalid_r ? 1'b1 :
                 m_axi_awready         ? 1'b0 :
                                         awvalid_r;
  end
end

assign m_axi_awaddr = addr;

always @(posedge aclk) begin
  addr <= start  ? addr_offset_r :
          awxfer ? addr + LP_DW_BYTES*LP_AXI_BURST_LEN :
                   addr;
end

assign m_axi_awlen   = aw_final_transaction || (start & single_transaction) ? final_burst_len : LP_AXI_BURST_LEN- 1;

  // When ar_idle, there are no transactions to issue.
  always @(posedge aclk) begin
    if (~areset) begin
      idle_aw <= 1'b1;
    end
    else begin
      idle_aw <= start   ? 1'b0 :
                 awxfer ? 1'b1 :
                           idle_aw;
    end
  end


always @(posedge aclk) begin
  wfirst_d1 <= m_axi_wvalid & wfirst;
end

always @(posedge aclk) begin
  wfirst_pulse <= m_axi_wvalid & wfirst & ~wfirst_d1;
end

  assign aw_final_transaction = 1'b1;

  /////////////////////////////////////////////////////////////////////////////
  // AXI Write Response Channel
  /////////////////////////////////////////////////////////////////////////////
  assign m_axi_bready = 1'b1;
  assign bxfer = m_axi_bready & m_axi_bvalid;
  
  assign BVld_O = bxfer;


endmodule : AlephMiner_axi_write_master

`default_nettype wire


