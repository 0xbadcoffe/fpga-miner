// === axim_alephminer.sv ===

module axim_alephminer 
	#(C_M00_AXI_ADDR_WIDTH = 64, 
    C_M00_AXI_DATA_WIDTH = 32)
  (
  // System Signals
  input                                ap_clk         ,
  input                                ap_rst_n       ,
  // AXI4 master interface m00_axi
  output                               m00_axi_awvalid,
  input                                m00_axi_awready,
  output  [C_M00_AXI_ADDR_WIDTH-1:0]   m00_axi_awaddr ,
  output  [8-1:0]                      m00_axi_awlen  ,
  output                               m00_axi_wvalid ,
  input                                m00_axi_wready ,
  output  [C_M00_AXI_DATA_WIDTH-1:0]   m00_axi_wdata  ,
  output  [C_M00_AXI_DATA_WIDTH/8-1:0] m00_axi_wstrb  ,
  output                               m00_axi_wlast  ,
  input                                m00_axi_bvalid ,
  output                               m00_axi_bready ,
  output                               m00_axi_arvalid,
  input                                m00_axi_arready,
  output  [C_M00_AXI_ADDR_WIDTH-1:0]   m00_axi_araddr ,
  output  [8-1:0]                      m00_axi_arlen  ,
  input                                m00_axi_rvalid ,
  output                               m00_axi_rready ,
  input   [C_M00_AXI_DATA_WIDTH-1:0]   m00_axi_rdata  ,
  input                                m00_axi_rlast  ,
  // Control Signals
  input                                ap_start       ,
  output                               ap_idle        ,
  output                               ap_done        ,
  output                               ap_ready       ,
  input   [7:0]                        FromGroup      ,
  input   [7:0]                        ToGroup        ,
  input   [7:0]                        Groups         ,
  input   [7:0]                        GroupsShifter  ,
  input   [7:0]                        ChainNum       ,
  input   [15:0]                       ChunkLength    ,
  input   [63:0]                       TargetIn       ,
  input   [63:0]                       HeaderBlobIn   ,
  input   [63:0]                       Nonce          ,
  input   [63:0]                       HashCounterOut ,
  input   [63:0]                       HashOut        
);

  // states for the FSM
  typedef enum {RD_IDLE, TARGET_ST, NONCE_ST, HEADERBLOB_ST} state_t;
  typedef enum {WR_IDLE, WR_NONCE, HASHCNTR_ST, HASH_ST} wr_state_t;
  
  ///////////////////////////////////////////////////////////////////////////////
  // Local Parameters
  ///////////////////////////////////////////////////////////////////////////////
  // Large enough for interesting traffic.
  localparam integer  LP_DEFAULT_LENGTH_IN_BYTES = 16384;
  localparam integer  LP_NUM_EXAMPLES    = 1;
  localparam integer  LP_DW_BYTES             = C_M00_AXI_DATA_WIDTH/8;
  localparam integer  LP_AXI_BURST_LEN        = 4096/LP_DW_BYTES < 256 ? 4096/LP_DW_BYTES : 256;
  localparam integer  LP_LOG_BURST_LEN        = $clog2(LP_AXI_BURST_LEN);

  localparam integer  LP_TARGET_BYTES         = 32;
  localparam integer  LP_NONCE_BYTES          = 24;
  localparam integer  LP_HEADERBLOB_BYTES     = 264;
  
  localparam integer  LP_TARGET_NUM           = LP_TARGET_BYTES>>2;
  localparam integer  LP_NONCE_NUM            = LP_NONCE_BYTES>>2;
  localparam integer  LP_HEADERBLOB_NUM       = LP_HEADERBLOB_BYTES>>2;

  ///////////////////////////////////////////////////////////////////////////////
  // Wires and Variables
  ///////////////////////////////////////////////////////////////////////////////
  (* KEEP = "yes" *)
  logic                                areset_n                       = 1'b0;
  logic                                ap_start_r                     = 1'b0;
  logic                                ap_idle_r                      = 1'b1;
  logic                                ap_start_pulse                ;
  logic [LP_NUM_EXAMPLES-1:0]          write_done                    ;
  logic [LP_NUM_EXAMPLES-1:0]          ap_done_r                      = {LP_NUM_EXAMPLES{1'b0}};
  logic [32-1:0]                       ctrl_xfer_size_in_bytes        = LP_DEFAULT_LENGTH_IN_BYTES;
  logic [C_M00_AXI_ADDR_WIDTH-1:0]     ctrl_addr_offset               = 'b0;
  logic [32-1:0]                       ctrl_constant                  = 32'd1;
  logic [32-1:0]                       write_xfer_size_in_bytes       = LP_DEFAULT_LENGTH_IN_BYTES;
  logic [C_M00_AXI_ADDR_WIDTH-1:0]     write_addr_offset              = 'b0;

  logic [31:0] group_directions;
  logic [31:0] groups_w;
  logic [31:0] chunk_length;

  // FSM read
  state_t next_state;
  state_t state = RD_IDLE;
  integer idx;

  // AXI4 Read Master
  logic read_start = 1'b0;
  logic [31:0] rd_data;
  logic vld;

  // AleMiner
  logic update_miner;
  logic [(LP_TARGET_BYTES>>2)-1:0][31:0] target;
  logic [(LP_NONCE_BYTES>>2)-1:0][31:0] nonce;

  logic [31:0] headerblob;
  logic wr;

  logic miner_rdy;
  logic [LP_NONCE_NUM-1:0][31:0] vld_nonce;
  logic [7:0][31:0] hash;
  
  logic [31:0] hash_cntr;

  // FSM write
  wr_state_t next_wr_state;
  wr_state_t wr_state = WR_IDLE;
  integer wr_idx;
  logic full_wr_done;

  // AXI4 Write Master
  logic write_start = 1'b0;
  logic wr_vld;
  logic wr_rdy;
  logic [31:0] wr_data;
  logic wr_bvld;

  ///////////////////////////////////////////////////////////////////////////////
  // Begin RTL
  ///////////////////////////////////////////////////////////////////////////////


  // Register reset signal.
  always @(posedge ap_clk) begin
    areset_n <= ap_rst_n;
  end
  
  // create pulse when ap_start transitions to 1
  always @(posedge ap_clk) begin
    begin
      ap_start_r <= ap_start;
    end
  end
  
  assign ap_start_pulse = ap_start & ~ap_start_r;
  
  // ap_idle is asserted when done is asserted, it is de-asserted when ap_start_pulse
  // is asserted
  always @(posedge ap_clk) begin
    if (~areset_n) begin
      ap_idle_r <= 1'b1;
    end
    else begin
      ap_idle_r <= ap_done ? 1'b1 :
        ap_start_pulse ? 1'b0 : ap_idle;
    end
  end
  
  assign ap_idle = ap_idle_r;
  
  // Done logic
  always @(posedge ap_clk) begin
    if (~areset_n) begin
      ap_done_r <= '0;
    end
    else begin
      ap_done_r <= (ap_done) ? '0 : ap_done_r | full_wr_done;
    end
  end
  
  assign ap_done = &ap_done_r;
  
  // Ready Logic (non-pipelined case)
  assign ap_ready = ap_done;

  //////////////
  // READ FSM //
  //////////////

  // seq logic
  always_ff@(posedge ap_clk or negedge ap_rst_n)
  begin : state_sync
    if(~ap_rst_n)
      state <= RD_IDLE;
    else
      state <= next_state;
  end
  
  // next state decoder
  always_comb
  begin : next_state_decode
    next_state <= state;
    case (state)
    
      RD_IDLE: begin
        if(ap_start_pulse)
          next_state <= TARGET_ST;
      end//RD_IDLE
      
      TARGET_ST: begin
        if(ap_start_pulse)
          next_state <= TARGET_ST;
        else if(idx==LP_TARGET_NUM)
          next_state <= NONCE_ST;
      end//TARGET_ST

      NONCE_ST: begin
        if(ap_start_pulse)
          next_state <= TARGET_ST;
        else if(idx==LP_NONCE_NUM)
          next_state <= HEADERBLOB_ST;
      end//NONCE_ST
      
      HEADERBLOB_ST: begin
        if(ap_start_pulse)
          next_state <= TARGET_ST;
        else if(idx==LP_HEADERBLOB_NUM)
          next_state <= RD_IDLE;
      end//HEADERBLOB_ST

      default:
          next_state <= state;
    endcase
  end
  
  //sequential FSM
  always_ff@(posedge ap_clk or negedge ap_rst_n)
  begin : fsm_seq
    if(~ap_rst_n) begin
      read_start <= 1'b0;
      target <= 0;
      nonce <= 0;
      headerblob <= 0;
      wr <= 0;
      idx <= 0;
      update_miner <= 1'b0;
    end  
    else begin
      read_start <= 1'b0;
      case (state)
      
        RD_IDLE: begin
          wr <= 1'b0;
          update_miner <= 1'b0;
          idx <= 0;
          if(ap_start_pulse) begin
            read_start <= 1'b1;
            ctrl_addr_offset <= TargetIn;
            ctrl_xfer_size_in_bytes <= LP_TARGET_BYTES; 
          end
        end//RD_IDLE
        
        TARGET_ST: begin
          update_miner <= 1'b0;
          if(vld) begin
            target[idx] <= rd_data;
            idx <= idx + 1;
          end
          if(idx==LP_TARGET_NUM) begin
            idx <= 0;
            read_start <= 1'b1;
            ctrl_addr_offset <= Nonce;
            ctrl_xfer_size_in_bytes <= LP_NONCE_BYTES;
          end
        end//TARGET_ST

        NONCE_ST: begin
          if(vld) begin
            nonce[idx] <= rd_data;
            idx <= idx + 1;
          end 
          if(idx==LP_NONCE_NUM) begin
            update_miner <= 1'b1;
            read_start <= 1'b1;
            idx <= 0;
            ctrl_addr_offset <= HeaderBlobIn;
            ctrl_xfer_size_in_bytes <= LP_HEADERBLOB_BYTES; 
          end
        end//NONCE_ST
        
        HEADERBLOB_ST: begin
          update_miner <= 1'b0;
          if(vld) begin
            headerblob <= rd_data;
            wr <= 1'b1;
            idx <= idx + 1;
          end
          else
            wr <= 1'b0;
        end//HEADERBLOB_ST
        
        default: begin
          read_start <= 1'b0;
          target <= 0;
          nonce <= 0;
          headerblob <= 0;
          wr <= 0;
          idx <= 0;
          update_miner <= 1'b0;
        end// default
        
      endcase
    end
  end



  // AXI4 Read Master, output format is an AXI4-Stream master, one stream per thread.
  AlephMiner_axi_read_master #(
    .C_M_AXI_ADDR_WIDTH  ( C_M00_AXI_ADDR_WIDTH  ) ,
    .C_M_AXI_DATA_WIDTH  ( C_M00_AXI_DATA_WIDTH  ) ,
    .C_XFER_SIZE_WIDTH   ( 32   ) 
  )
  inst_axi_read_master (
    .aclk                    ( ap_clk                  ) ,
    .areset                  ( areset_n                ) ,
    .ctrl_start              ( read_start              ) ,
    .ctrl_done               ( read_done               ) ,
    .ctrl_addr_offset        ( ctrl_addr_offset        ) ,
    .ctrl_xfer_size_in_bytes ( ctrl_xfer_size_in_bytes ) ,
    .m_axi_arvalid           ( m00_axi_arvalid         ) ,
    .m_axi_arready           ( m00_axi_arready         ) ,
    .m_axi_araddr            ( m00_axi_araddr          ) ,
    .m_axi_arlen             ( m00_axi_arlen           ) ,
    .m_axi_rvalid            ( m00_axi_rvalid          ) ,
    .m_axi_rready            ( m00_axi_rready          ) ,
    .m_axi_rdata             ( m00_axi_rdata           ) ,
    .m_axi_rlast             ( m00_axi_rlast           ) ,
    .Vld_O                   ( vld ),
    .Data_O                  ( rd_data )
  );


  assign group_directions = {{8{1'b0}},FromGroup,{8{1'b0}},ToGroup};
  assign groups_w =  {{8{1'b0}},Groups,ChainNum,GroupsShifter};
  assign chunk_length = {{15{1'b0}},ChunkLength};


  AleMiner AleMiner_i
  (
    .Clk(ap_clk),
    .Rst_n(areset_n),
    .UpdateTrigger_I(update_miner),
    .GroupDirections_I(group_directions),
    .Groups_I(groups_w),
    .ChunkLength_I(chunk_length),
    .Target_I(target),
    .Nonce_I(nonce),
    .Wr_I(wr),
    .Data_I(headerblob),
    .VldNonce_O(miner_rdy),
    .Nonce_O(vld_nonce),
    .HashCounter_O(hash_cntr),
    .Hash_O(hash),
    .Irq_O() 
  );

  ///////////////
  // WRITE FSM //
  ///////////////

  // seq logic
  always_ff@(posedge ap_clk or negedge ap_rst_n)
  begin : wr_state_sync
    if(~ap_rst_n)
      wr_state <= WR_IDLE;
    else
      wr_state <= next_wr_state;
  end
  
  // next state decoder
  always_comb
  begin : next_wr_state_decode
    next_wr_state <= wr_state;
    case (wr_state)
    
      WR_IDLE: begin
        if(miner_rdy && !ap_start_pulse)
          next_wr_state <= WR_NONCE;
      end//WR_IDLE
      
      WR_NONCE: begin
        if(ap_start_pulse)
          next_wr_state <= WR_IDLE;
        else if(wr_bvld)
          next_wr_state <= HASHCNTR_ST;
      end//NONCE_ST

      HASHCNTR_ST: begin
        if(ap_start_pulse)
          next_wr_state <= WR_IDLE;
        else if(wr_bvld)
          next_wr_state <= HASH_ST;
      end//HASHCNTR_ST
      
      HASH_ST: begin
        if(ap_start_pulse || wr_bvld)
          next_wr_state <= WR_IDLE;
      end//HASH_ST

      default:
          next_wr_state <= wr_state;
    endcase
  end
  
  //sequential FSM
  always_ff@(posedge ap_clk or negedge ap_rst_n)
  begin : wr_fsm_seq
    if(~ap_rst_n) begin
      wr_vld <= 1'b0;
      wr_data <= 1'b0;
      write_addr_offset <= 0;
      write_xfer_size_in_bytes <= 0;
      write_start <= 1'b0;
      wr_idx <= 0;
    end  
    else begin
      write_start <= 1'b0;
      case (wr_state)
      
        WR_IDLE: begin
          wr_vld <= 1'b0;
          wr_idx <= 0;
          write_addr_offset <= 0;
          write_xfer_size_in_bytes <= 0;
          wr_data <= 0;
          if(miner_rdy) begin
            write_start <= 1'b1;
            write_addr_offset <= Nonce;
            write_xfer_size_in_bytes <= LP_NONCE_BYTES;
            wr_data <= vld_nonce[0];
            wr_idx <= 1;
          end
        end//IDLE
        
        WR_NONCE: begin
          if(wr_idx < (LP_NONCE_NUM+1))
            wr_vld <= 1'b1;
          else
            wr_vld <= 1'b0;
          if(wr_rdy && wr_vld) begin
            wr_data <= nonce[wr_idx];
            wr_idx <= wr_idx + 1;
          end
          if(wr_bvld) begin
            wr_idx <= 0;
            write_start <= 1'b1;
            write_addr_offset <= HashCounterOut;
            write_xfer_size_in_bytes <= 4;
            wr_data <= hash_cntr;
          end
        end//NONCE_ST

        HASHCNTR_ST: begin
          if(wr_idx < 1)
            wr_vld <= 1'b1;
          else
            wr_vld <= 1'b0;
          if(wr_rdy && wr_vld)
            wr_idx <= 1;
          if(wr_bvld) begin
            wr_idx <= 1;
            write_start <= 1'b1;
            write_addr_offset <= HashOut;
            write_xfer_size_in_bytes <= LP_TARGET_BYTES;
            wr_data <= hash[0];
          end
        end//HASHCNTR_ST
        
        HASH_ST: begin
          if(wr_idx < (LP_TARGET_NUM+1))
            wr_vld <= 1'b1;
          else
            wr_vld <= 1'b0;
          if(wr_rdy && wr_vld) begin
            wr_data <= hash[wr_idx];
            wr_idx <= wr_idx + 1;
          end
        end//HASH_ST
        
        default: begin
          wr_vld <= 1'b0;
          wr_data <= 1'b0;
          write_addr_offset <= 0;
          write_xfer_size_in_bytes <= 0;
          write_start <= 1'b0;
          wr_idx <= 0;
        end// default
        
      endcase
    end
  end
  
  assign full_wr_done = (wr_state==WR_IDLE) ? write_done : 1'b0;


  // AXI4 Write Master
  AlephMiner_axi_write_master #(
    .C_M_AXI_ADDR_WIDTH  ( C_M00_AXI_ADDR_WIDTH    ) ,
    .C_M_AXI_DATA_WIDTH  ( C_M00_AXI_DATA_WIDTH    ) ,
    .C_XFER_SIZE_WIDTH   ( 32     )
  )
  inst_axi_write_master (
    .aclk                    ( ap_clk                  ) ,
    .areset                  ( areset_n                ) ,
    .ctrl_start              ( write_start             ) ,
    .ctrl_done               ( write_done              ) ,
    .ctrl_addr_offset        ( write_addr_offset       ) ,
    .ctrl_xfer_size_in_bytes ( write_xfer_size_in_bytes) ,
    .m_axi_awvalid           ( m00_axi_awvalid         ) ,
    .m_axi_awready           ( m00_axi_awready         ) ,
    .m_axi_awaddr            ( m00_axi_awaddr          ) ,
    .m_axi_awlen             ( m00_axi_awlen           ) ,
    .m_axi_wvalid            ( m00_axi_wvalid          ) ,
    .m_axi_wready            ( m00_axi_wready          ) ,
    .m_axi_wdata             ( m00_axi_wdata           ) ,
    .m_axi_wstrb             ( m00_axi_wstrb           ) ,
    .m_axi_wlast             ( m00_axi_wlast           ) ,
    .m_axi_bvalid            ( m00_axi_bvalid          ) ,
    .m_axi_bready            ( m00_axi_bready          ) ,
    .Vld_I                   ( wr_vld                  ) ,
    .Rdy_O                   ( wr_rdy                  ) ,
    .Data_I                  ( wr_data                 ) ,
    .BVld_O                  ( wr_bvld                 )
  );
 


endmodule : axim_alephminer
