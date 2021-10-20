// This is a generated file. Use and modify at your own risk.
////////////////////////////////////////////////////////////////////////////////

// Description:
// This is an AXI4 read master module example. The module demonstrates how to
// issue AXI read transactions to a memory mapped slave.  Given a starting
// address offset and a transfer size in bytes, it will issue one or more AXI
// transactions and return the data over an AXI4-Stream interface.
//
// Theory of operation:
// It uses a minimum subset of the AXI4 protocol by omitting AXI4 signals that
// are not used.  When packaged as a kernel or IP, this allows for
// optimizations to occur within the AXI Interconnect system to increase Fmax,
// potentially increase performance, and reduce latency/area. When
// C_INCLUDE_DATA_FIFO is set to 1, a data FIFO is included and configured so
// that all transactions that are issued can fit into the FIFO.  This allows
// for m_axi_rready to be tied high, and ensures that an unexpected stall
// internally does not cause the AXI Interconnect system to become
// inadvertantly deadlocked or cause head of line blocking to other AXI masters
// in the system.
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
//    This value will be rounded up to the nearest multiple of the interface width.
//    For example a request of 100 bytes will be rounded up to 128 bytes on a 64 byte
//    (512 bits) wide interface.
// 3) Assert ctrl_start for once cycle.  At the posedge, the ctrl_addr_offset and
//    ctrl_xfer_size_in_bytes will be registered in the module, and will start
//    issue read address transfers.  If the the transfer size is larger than 4096
//    bytes, multiple transactions will be issued.  There may be up to the
//    C_MAX_OUTSTANDING issued in succession.  Once the limit is hit
//    no more read address transfers on the AR channel will be issued until
//    R channel transactions have completed as indicated by the RLAST signal.
// 4) Read Data will appear on the AXI4-Stream interface (m_axis) as signalled by
//    an assertion of the m_axis_tvalid signal.
// 5) When the final R-channel transaction has completed, the module will assert
//    the ctrl_done signal for one cycle.  If a data FIFO is present, data may
//    still be present in the FIFO.
// 6) Jump to step 1.
////////////////////////////////////////////////////////////////////////////////

// default_nettype of none prevents implicit wire declaration.
`default_nettype none

module AlephMiner_axi_read_master #(
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
  // System signals
  input  wire                          aclk,
  input  wire                          areset,

  // Control signals
  input  wire                          ctrl_start,              // Pulse high for one cycle to begin reading
  output wire                          ctrl_done,               // Pulses high for one cycle when transfer request is complete

  // The following ctrl signals are sampled when ctrl_start is asserted
  input  wire [C_M_AXI_ADDR_WIDTH-1:0] ctrl_addr_offset,        // Starting Address offset
  input  wire [C_XFER_SIZE_WIDTH-1:0]  ctrl_xfer_size_in_bytes, // Length in number of bytes, limited by the address width.

  // AXI4 master interface (read only)
  output wire                          m_axi_arvalid,
  input  wire                          m_axi_arready,
  output wire [C_M_AXI_ADDR_WIDTH-1:0] m_axi_araddr,
  output wire [8-1:0]                  m_axi_arlen,

  input  wire                          m_axi_rvalid,
  output wire                          m_axi_rready,
  input  wire [C_M_AXI_DATA_WIDTH-1:0] m_axi_rdata,
  input  wire                          m_axi_rlast,

  // Data interface for the miner
  output wire                          Vld_O,
  output wire [C_M_AXI_DATA_WIDTH-1:0] Data_O 

);

timeunit 1ps;
timeprecision 1ps;
///////////////////////////////////////////////////////////////////////////////
// functions
///////////////////////////////////////////////////////////////////////////////
function integer f_max (
  input integer a,
  input integer b
);
  f_max = (a > b) ? a : b;
endfunction

function integer f_min (
  input integer a,
  input integer b
);
  f_min = (a < b) ? a : b;
endfunction

///////////////////////////////////////////////////////////////////////////////
// Local Parameters
///////////////////////////////////////////////////////////////////////////////
localparam integer LP_DW_BYTES                   = C_M_AXI_DATA_WIDTH/8;
localparam integer LP_LOG_DW_BYTES               = $clog2(LP_DW_BYTES);
localparam integer LP_MAX_BURST_LENGTH           = 256;   // Max AXI Protocol burst length
localparam integer LP_MAX_BURST_BYTES            = 4096;  // Max AXI Protocol burst size in bytes
localparam integer LP_AXI_BURST_LEN              = f_min(LP_MAX_BURST_BYTES/LP_DW_BYTES, LP_MAX_BURST_LENGTH);
localparam integer LP_LOG_BURST_LEN              = $clog2(LP_AXI_BURST_LEN);
localparam integer LP_TOTAL_LEN_WIDTH            = C_XFER_SIZE_WIDTH-LP_LOG_DW_BYTES;
localparam integer LP_TRANSACTION_CNTR_WIDTH     = LP_TOTAL_LEN_WIDTH-LP_LOG_BURST_LEN;
localparam [C_M_AXI_ADDR_WIDTH-1:0] LP_ADDR_MASK = LP_DW_BYTES*LP_AXI_BURST_LEN - 1;

///////////////////////////////////////////////////////////////////////////////
// Variables
///////////////////////////////////////////////////////////////////////////////
// Control logic
logic                                     done = '0;
logic                                     has_partial_bursts;
logic                                     start_d1 = 1'b0;
logic [C_M_AXI_ADDR_WIDTH-1:0]            addr_offset_r;
logic                                     start    = 1'b0;
logic [LP_TOTAL_LEN_WIDTH-1:0]            total_len_r;
logic [LP_TRANSACTION_CNTR_WIDTH-1:0]     num_transactions;
logic [LP_LOG_BURST_LEN-1:0]              final_burst_len;
logic                                     single_transaction;
logic                                     ar_idle = 1'b1;
logic                                     ar_done;
// AXI Read Address Channel
logic                                     arxfer;
logic                                     arvalid_r = 1'b0;
logic [C_M_AXI_ADDR_WIDTH-1:0]            addr;

// AXI Data Channel
logic                                     rxfer;
logic                                     r_completed;
logic                                     ar_completed;


logic [C_XFER_SIZE_WIDTH-1:0]  r_cntr;
logic [C_M_AXI_DATA_WIDTH-1:0] data_r;
logic                          vld_r; 

///////////////////////////////////////////////////////////////////////////////
// Control Logic
///////////////////////////////////////////////////////////////////////////////

always @(posedge aclk) begin
  done <= rxfer & m_axi_rlast & r_completed ? 1'b1 : ctrl_done ? 1'b0 : done;
end

assign ctrl_done = done;

always @(posedge aclk) begin
  start_d1 <= ctrl_start;
end

// Store the address and transfer size after some pre-processing.
always @(posedge aclk) begin
  if (ctrl_start) begin
    // Round transfer size up to integer value of the axi interface data width. Convert to axi_arlen format which is length -1.
    total_len_r <= ctrl_xfer_size_in_bytes[0+:LP_LOG_DW_BYTES] > 0
                      ? ctrl_xfer_size_in_bytes[LP_LOG_DW_BYTES+:LP_TOTAL_LEN_WIDTH]
                      : ctrl_xfer_size_in_bytes[LP_LOG_DW_BYTES+:LP_TOTAL_LEN_WIDTH] - 1'b1;
    // Align transfer to 4kB to avoid AXI protocol issues if starting address is not correctly aligned.
    addr_offset_r <= ctrl_addr_offset & ~LP_ADDR_MASK;
  end
end

// Determine how many full burst to issue and if there are any partial bursts.
assign num_transactions = total_len_r[LP_LOG_BURST_LEN+:LP_TRANSACTION_CNTR_WIDTH];
assign has_partial_bursts = total_len_r[0+:LP_LOG_BURST_LEN] == {LP_LOG_BURST_LEN{1'b1}} ? 1'b0 : 1'b1;

always @(posedge aclk) begin
  start <= start_d1;
  final_burst_len <=  total_len_r[0+:LP_LOG_BURST_LEN];
end

// Special case if there is only 1 AXI transaction.
assign single_transaction = (num_transactions == {LP_TRANSACTION_CNTR_WIDTH{1'b0}}) ? 1'b1 : 1'b0;

///////////////////////////////////////////////////////////////////////////////
// AXI Read Address Channel
///////////////////////////////////////////////////////////////////////////////
assign m_axi_arvalid = arvalid_r;
assign m_axi_araddr = addr;
assign m_axi_arlen  = single_transaction ? final_burst_len : LP_AXI_BURST_LEN - 1;

assign arxfer = m_axi_arvalid & m_axi_arready;

always @(posedge aclk) begin
  if (~areset) begin
    arvalid_r <= 1'b0;
  end
  else begin
    arvalid_r <= ~ar_idle & ~ar_completed & ~arvalid_r ? 1'b1 :
                 m_axi_arready ? 1'b0 : arvalid_r;
  end
end

// When ar_idle, there are no transactions to issue.
always @(posedge aclk) begin
  if (~areset) begin
    ar_idle <= 1'b1;
  end
  else begin
    ar_idle <= start   ? 1'b0 :
               ar_done ? 1'b1 :
                         ar_idle;
  end
end

// Increment to next address after each transaction is issued.
always @(posedge aclk) begin
  addr <= start ? addr_offset_r :
          arxfer     ? addr + LP_AXI_BURST_LEN*C_M_AXI_DATA_WIDTH/8 :
                       addr;
end


assign ar_done = arxfer;

  always@(posedge aclk or negedge areset)
  begin : ar_counter
    if(~areset)
      ar_completed <= 0;
    else if(ctrl_start)
      ar_completed <= 0;
    else if(arxfer && !ar_completed)
      ar_completed <= 1'b1;
  end


  always@(posedge aclk or negedge areset)
  begin : r_counter
    if(~areset)
      r_cntr <= 0;
    else if(ctrl_start)
      r_cntr <= 0;
    else if(rxfer && !r_completed)
      r_cntr <= r_cntr + 4;
  end

assign r_completed = (r_cntr == ctrl_xfer_size_in_bytes);

///////////////////////////////////////////////////////////////////////////////
// AXI Read Channel
///////////////////////////////////////////////////////////////////////////////

  assign m_axi_rready  = 1'b1;
  assign rxfer = m_axi_rready & m_axi_rvalid;

  always@(posedge aclk or negedge areset)
  begin : data_register
    if(~areset) begin
      data_r <= 0;
      vld_r <= 0;
    end 
    else begin
      vld_r <= m_axi_rvalid;
      if(m_axi_rvalid)
        data_r <= m_axi_rdata;
    end
  end

  assign Data_O = data_r;
  assign Vld_O = vld_r;

endmodule : AlephMiner_axi_read_master

`default_nettype wire

