// === axim_alephminer.sv ===

module axim_alephminer 
	#(C_M00_AXI_ADDR_WIDTH = 64, 
    C_M00_AXI_DATA_WIDTH = 32,
    INST_NUM = 2
  )
  (
  // System Signals
  input                                ap_clk         ,
  input                                ap_rst_n       ,
  input                                ap_clk_2       ,
  input                                ap_rst_n_2     ,
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
  input   [31:0]                       MiningSteps    ,
  input   [63:0]                       Data           ,
  input   [63:0]                       Results        
);

  // states for the FSM
  typedef enum {RD_IDLE, TARGET_ST, NONCE_ST, HEADERBLOB_ST} state_t;
  typedef enum {WR_IDLE, WR_NONCE, HASHCNTR_ST, HASH_ST, DONE_ST} wr_state_t;
  
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
  
  localparam integer  LP_TARGET_NUM           = LP_TARGET_BYTES>>2;
  localparam integer  LP_NONCE_NUM            = LP_NONCE_BYTES>>2;

  localparam integer  LP_ALL_NONCE_BYTES      = LP_NONCE_BYTES*INST_NUM;
  localparam integer  LP_ALL_NONCE_NUM        = LP_ALL_NONCE_BYTES>>2;
  

  // word/byte number of NONCE, HASHCOUNTER and HASH
  localparam integer  LP_RESULTS_BYTES         = LP_NONCE_BYTES + 4 + LP_TARGET_BYTES;
  localparam integer  LP_RESULTS_NUM           = LP_NONCE_NUM + 1 + LP_TARGET_NUM;

  localparam integer  LP_RD_FIFO_DEPTH         = 128;
  localparam integer  LP_RD_FIFO_PROG_FULL     = LP_TARGET_NUM + LP_ALL_NONCE_NUM + 76;
  localparam integer  LP_WR_FIFO_DEPTH         = LP_TARGET_NUM + LP_NONCE_NUM + 2; //16 is the minimum

  ///////////////////////////////////////////////////////////////////////////////
  // Wires and Variables
  ///////////////////////////////////////////////////////////////////////////////
  (* KEEP = "yes" *)
  logic                                areset_n                       = 1'b0;
  logic                                areset_n_2                     = 1'b0;
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
  logic rd_valid;


  // RD FIFO
  logic rd_fifo_rd_en; 
  logic rd_fifo_rdy;     
  logic [31:0] rd_fifo_data;     
  logic rd_fifo_valid_n;
 
  // AleMiner
  logic update_miner;
  logic [(LP_TARGET_BYTES>>2)-1:0][31:0] target;
  logic [(LP_NONCE_NUM*INST_NUM)-1:0][31:0] nonce;

  logic [31:0] headerblob;
  logic wr;

  logic [INST_NUM-1:0] miner_rdy;
  logic invld_hash;
  logic invld_hash_reg;
  logic invld_hash_pulse;
  logic miner_rdy_reg = 1'b0;
  logic [INST_NUM-1:0][LP_NONCE_NUM-1:0][31:0] vld_nonce;
  logic [INST_NUM-1:0][LP_TARGET_NUM-1:0][31:0] hash;

  logic [LP_NONCE_NUM-1:0][31:0] winner_nonce = 0;
  logic [LP_TARGET_NUM-1:0][31:0] winner_hash = 0;
  
  logic [INST_NUM-1:0][31:0] hash_cntr;
  //accumulated hash counter
  logic [31:0] acc_hash_cntr = 0;

  // FSM write
  wr_state_t next_wr_state;
  wr_state_t wr_state = WR_IDLE;
  integer wr_idx;
  logic full_wr_done;
  
  // WR FIFO
  logic wr_en = 1'b0;
  logic write_burst = 1'b0;
  logic [31:0] wr_fifo_data;
  
  // AXI4 Write Master
  logic write_start = 1'b0;
  logic wr_vld;
  logic wr_rdy;
  logic [31:0] wr_data;
  logic wr_bvld;
  
  logic [31:0] headerblob_bytes;
  logic [31:0] headerblob_num;
  
  logic [31:0] data_bytes;
  logic [31:0] data_num;

  // sync with the 2nd clock
  logic [1:0] ap_done_2 = 0;
  logic [1:0][31:0] group_directions_2;
  logic [1:0][31:0] groups_2;
  logic [1:0][31:0] chunk_length_2;
  logic [1:0][31:0] headerblob_num_2;

  ///////////////////////////////////////////////////////////////////////////////
  // Begin RTL
  ///////////////////////////////////////////////////////////////////////////////
  
  assign headerblob_bytes = ChunkLength - LP_NONCE_BYTES;
  
  always@(posedge ap_clk) begin
     if (~areset_n)
        headerblob_num <= 0;
    else if (headerblob_bytes[1:0] != 0)
        headerblob_num <= (headerblob_bytes>>2) + 1;
    else
        headerblob_num <= headerblob_bytes>>2;
  end
  
  assign data_bytes = LP_TARGET_BYTES + LP_ALL_NONCE_BYTES + headerblob_bytes;
  assign data_num =LP_TARGET_NUM + LP_ALL_NONCE_NUM + headerblob_num;
 
  assign group_directions = {{8{1'b0}},FromGroup,{8{1'b0}},ToGroup};
  assign groups_w =  {{8{1'b0}},Groups,ChainNum,GroupsShifter};
  assign chunk_length = {{15{1'b0}},ChunkLength};



  // Register reset signal.
  always @(posedge ap_clk) begin
    areset_n <= ap_rst_n;
  end

  // Register reset signal.
  always @(posedge ap_clk_2) begin
    areset_n_2 <= ap_rst_n_2;
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

  // AXI3 Read Master, output format is an AXI4-Stream master, one stream per thread.
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
    .Vld_O                   ( rd_valid ),
    .Data_O                  ( rd_data )
  );

  ///////////////
  // READ CTRL //
  ///////////////

  always_ff@(posedge ap_clk or negedge ap_rst_n)
  begin : read_control
    if(~ap_rst_n) begin
      read_start <= 0;
      ctrl_addr_offset <= 0; 
      ctrl_xfer_size_in_bytes <= 0; 
    end
    else if(ap_start_pulse) begin
      read_start <= 1'b1;
      ctrl_addr_offset <= Data;
      ctrl_xfer_size_in_bytes <= data_bytes; 
    end
    else
      read_start <= 0;
   end


  // xpm_fifo_async: Asynchronous FIFO
  // Xilinx Parameterized Macro, Version 2016.4
  xpm_fifo_async # (
    .FIFO_MEMORY_TYPE          ("auto"),           //string; "auto", "block", "distributed", or "ultra";
    .ECC_MODE                  ("no_ecc"),         //string; "no_ecc" or "en_ecc";
    .RELATED_CLOCKS            (0),                //positive integer; 0 or 1
    .FIFO_WRITE_DEPTH          (LP_RD_FIFO_DEPTH),   //positive integer
    .WRITE_DATA_WIDTH          (C_M00_AXI_DATA_WIDTH),        //positive integer
    .WR_DATA_COUNT_WIDTH       ($clog2(LP_RD_FIFO_DEPTH)+1),       //positive integer, Not used
    .PROG_FULL_THRESH          (LP_RD_FIFO_PROG_FULL),               //positive integer
    .FULL_RESET_VALUE          (1),                //positive integer; 0 or 1
    .READ_MODE                 ("fwft"),            //string; "std" or "fwft";
    .FIFO_READ_LATENCY         (1),                //positive integer;
    .READ_DATA_WIDTH           (C_M00_AXI_DATA_WIDTH),               //positive integer
    .RD_DATA_COUNT_WIDTH       ($clog2(LP_RD_FIFO_DEPTH)+1),               //positive integer, not used
    .PROG_EMPTY_THRESH         (10),               //positive integer, not used 
    .DOUT_RESET_VALUE          ("0"),              //string, don't care
    .CDC_SYNC_STAGES           (3),                //positive integer
    .WAKEUP_TIME               (0)                 //positive integer; 0 or 2;
  
  ) inst_rd_xpm_fifo_async (
    .rst           ( ~areset_n        ) ,
    .wr_clk        ( ap_clk           ) ,
    .wr_en         ( rd_valid         ) ,
    .din           ( rd_data          ) ,
    .full          (                  ) ,
    .overflow      (                  ) ,
    .wr_rst_busy   (                  ) ,
    .rd_clk        ( ap_clk_2         ) ,
    .rd_en         ( rd_fifo_rd_en    ) ,
    .dout          ( rd_fifo_data     ) ,
    .empty         ( rd_fifo_valid_n  ) ,
    .underflow     (                  ) ,
    .rd_rst_busy   (                  ) ,
    .prog_full     ( rd_fifo_rdy      ) ,
    .wr_data_count (                  ) ,
    .prog_empty    (                  ) ,
    .rd_data_count (                  ) ,
    .sleep         ( 1'b0             ) ,
    .injectsbiterr ( 1'b0             ) ,
    .injectdbiterr ( 1'b0             ) ,
    .sbiterr       (                  ) ,
    .dbiterr       (                  ) 
  );


  //////////////
  // READ FSM //
  //////////////

  // seq logic
  always_ff@(posedge ap_clk_2 or negedge areset_n_2)
  begin : state_sync
    if(~areset_n_2)
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
        if(rd_fifo_rdy && (~rd_fifo_valid_n))
          next_state <= TARGET_ST;
      end//RD_IDLE
      
      TARGET_ST: begin
        if(ap_start_pulse)
          next_state <= RD_IDLE;
        else if((idx==(LP_TARGET_NUM-1)) && rd_fifo_rd_en)
          next_state <= NONCE_ST;
      end//TARGET_ST

      NONCE_ST: begin
        if(ap_start_pulse)
          next_state <= RD_IDLE;
        else if((idx==(LP_ALL_NONCE_NUM-1)) && rd_fifo_rd_en)
          next_state <= HEADERBLOB_ST;
      end//NONCE_ST
      
      HEADERBLOB_ST: begin
        if(ap_start_pulse)
          next_state <= TARGET_ST;
        else if(idx==(headerblob_num_2[1]-1))
          next_state <= RD_IDLE;
      end//HEADERBLOB_ST

      default:
          next_state <= state;
    endcase
  end

  
  //sequential FSM
  always_ff@(posedge ap_clk_2 or negedge areset_n_2)
  begin : fsm_seq
    if(~areset_n_2) begin
      target <= 0;
      nonce <= 0;
      headerblob <= 0;
      wr <= 0;
      idx <= 0;
      update_miner <= 1'b0;
      rd_fifo_rd_en <= 1'b0;
    end  
    else begin
      case (state)
      
        RD_IDLE: begin
          wr <= 1'b0;
          update_miner <= 1'b0;
          idx <= 0;
          if(rd_fifo_rdy && (~rd_fifo_valid_n))
            rd_fifo_rd_en <= 1'b1;
          else
            rd_fifo_rd_en <= 1'b0;
        end//RD_IDLE
        
        TARGET_ST: begin
          update_miner <= 1'b0;
          rd_fifo_rd_en <= 1'b1; 
          target[(LP_TARGET_NUM-1)-idx] <= rd_fifo_data;
          if(idx==(LP_TARGET_NUM-1)) begin
            idx <= 0;
          end else
            idx <= idx + 1;
        end//TARGET_ST

        NONCE_ST: begin
          rd_fifo_rd_en <= 1'b1; 
          nonce[(LP_ALL_NONCE_NUM-1)-idx] <= rd_fifo_data;            
          if(idx==(LP_ALL_NONCE_NUM-1)) begin
            update_miner <= 1'b1;
            idx <= 0;
          end
          else
            idx <= idx + 1;
        end//NONCE_ST
        
        HEADERBLOB_ST: begin
          update_miner <= 1'b0;      
          headerblob <= rd_fifo_data;
          if(idx<(headerblob_num_2[1])) begin
            wr <= 1'b1;
            idx <= idx + 1;
            rd_fifo_rd_en <= 1'b1; 
          end else begin
            wr <= 1'b0;
            rd_fifo_rd_en <= 1'b0;
          end         
        end//HEADERBLOB_ST
        
        default: begin
          rd_fifo_rd_en <= 1'b0;
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

  always_ff@(posedge ap_clk_2 or negedge areset_n_2)
  begin : sync_regs
    if(~areset_n_2) begin
      ap_done_2 <= 0;
      group_directions_2 <= 0;
      groups_2 <= 0;
      chunk_length_2 <= 0;
      headerblob_num_2 <= 0;
    end 
    else begin
      ap_done_2 <= {ap_done_2[0],ap_done};
      group_directions_2 <= {group_directions_2[0],group_directions};
      groups_2 <= {groups_2[0],groups_w};
      chunk_length_2 <= {chunk_length_2[0],chunk_length};
      headerblob_num_2 <= {headerblob_num_2[0],headerblob_num};
    end
  end




  generate //start of generate block
    genvar i;

    for (i=0; i<INST_NUM; i++) begin
      AleMiner AleMiner_i
      (
        .Clk(ap_clk_2),
        .Rst_n(areset_n_2),
        .UpdateTrigger_I(update_miner),
        .Clear_I(ap_done_2[1]),
        .GroupDirections_I(group_directions_2[1]),
        .Groups_I(groups_2[1]),
        .ChunkLength_I(chunk_length_2[1]),
        .Target_I(target),
        .Nonce_I(nonce[(LP_NONCE_NUM*(i+1)-1):LP_NONCE_NUM*i]),
        .Wr_I(wr),
        .Data_I(headerblob),
        .VldNonce_O(miner_rdy[i]),
        .Nonce_O(vld_nonce[i]),
        .HashCounter_O(hash_cntr[i]),
        .Hash_O(hash[i]),
        .Irq_O() 
      );
    end

  endgenerate


  /////////////////////////////////////////////
  // WINNER NONCE & HASHCOUNTER ACCUMULATION //
  /////////////////////////////////////////////
  
  always_ff@(posedge ap_clk_2 or negedge areset_n_2)
  begin : miner_ready_reg
    if(~areset_n_2)
      miner_rdy_reg <= 1'b0;
    // one of the miners found a valid value
    else
      miner_rdy_reg <= (|miner_rdy);
  end
  
  assign invld_hash = (hash_cntr[0]==MiningSteps && !miner_rdy_reg);
  
  always_ff@(posedge ap_clk_2 or negedge areset_n_2)
  begin : invalid_hash_reg
    if(~areset_n_2)
      invld_hash_reg <= 1'b0;
    // one of the miners found a valid value
    else if(ap_start_pulse)
      invld_hash_reg <= 1'b0;
    else if(invld_hash)
      invld_hash_reg <= 1'b1;
  end
  
  assign invld_hash_pulse = (!invld_hash_reg && invld_hash);

  always_ff@(posedge ap_clk_2 or negedge areset_n_2)
  begin : winner_nonce_mux
    if(~areset_n_2) begin
      winner_nonce <= 0;
    end
    // one of the miners found a valid value
    else if(|miner_rdy && wr_state==WR_IDLE) begin
      for(int i = 0; i < INST_NUM; i++) begin
        if (miner_rdy == (1 << i)) begin
          winner_nonce = vld_nonce[i];
          winner_hash = hash[i];
        end
      end
    end
  end

  always_ff@(posedge ap_clk_2 or negedge areset_n_2)
  begin : hash_counter_acc
    if(~areset_n_2)
      acc_hash_cntr <= 0;
    else if(update_miner) 
        acc_hash_cntr <= 0;
    // one of the miners found a valid value
    else if((|miner_rdy || invld_hash_pulse) && wr_state==WR_IDLE)  begin
      for(int i = 0; i < INST_NUM; i++) begin
          acc_hash_cntr += hash_cntr[i];
      end
    end
  end


  ///////////////
  // WRITE FSM //
  ///////////////

  // seq logic
  always_ff@(posedge ap_clk_2 or negedge areset_n_2)
  begin : wr_state_sync
    if(~areset_n_2)
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
        if((invld_hash_pulse ||  miner_rdy_reg) && !ap_start_pulse)
          next_wr_state <= WR_NONCE;
      end//WR_IDLE
      
      WR_NONCE: begin
        if(ap_start_pulse)
          next_wr_state <= WR_IDLE;
        else if(wr_idx==(LP_NONCE_NUM-1) && wr_en)
          next_wr_state <= HASHCNTR_ST;
      end//NONCE_ST

      HASHCNTR_ST: begin
        if(ap_start_pulse)
          next_wr_state <= WR_IDLE;
        else if(wr_en)
          next_wr_state <= HASH_ST;
      end//HASHCNTR_ST
      
      HASH_ST: begin
        if(ap_start_pulse)
          next_wr_state <= WR_IDLE;
        else if(wr_idx==(LP_TARGET_NUM-1) && wr_en)
          next_wr_state <= DONE_ST;
      end//HASH_ST
      
      DONE_ST: begin
        if(update_miner)
          next_wr_state <= WR_IDLE;
       end//DONE_ST

      default:
          next_wr_state <= wr_state;
    endcase
  end
  
  //sequential FSM
  always_ff@(posedge ap_clk_2 or negedge areset_n_2)
  begin : wr_fsm_seq
    if(~areset_n_2) begin
      wr_en <= 1'b0;
      wr_data <= 1'b0;
      wr_idx <= 0;
    end  
    else begin
      case (wr_state)
      
        WR_IDLE: begin
          wr_en <= 1'b0;
          wr_idx <= 0;
          wr_data <= 0;
          if(miner_rdy_reg || invld_hash_pulse) begin
            wr_en <= 1'b1;
            wr_data <= winner_nonce[(LP_NONCE_NUM-1)];
            wr_idx <= 1;
          end
        end//IDLE
        
        WR_NONCE: begin
          wr_en <= 1'b1;
          wr_data <= winner_nonce[(LP_NONCE_NUM-1)-wr_idx];
          if(wr_idx < (LP_NONCE_NUM-1)) begin           
            wr_idx <= wr_idx + 1;
          end
          else begin
            wr_idx <= 0; 
          end
        end//NONCE_ST

        HASHCNTR_ST: begin
          wr_en <= 1'b1;
          wr_data <= {invld_hash_reg,acc_hash_cntr[30:0]};
          wr_idx <= 0;            
        end//HASHCNTR_ST
        
        HASH_ST: begin
          if(wr_idx < (LP_TARGET_NUM))
            wr_en <= 1'b1;
          else
            wr_en <= 1'b0;
          wr_data <= winner_hash[(LP_TARGET_NUM-1)-wr_idx];
          wr_idx <= wr_idx + 1;
        end//HASH_ST
        
        default: begin
          wr_en <= 1'b0;
          wr_data <= 1'b0;
          wr_idx <= 0;
        end// default
        
      endcase
    end
  end


  // xpm_fifo_async: Asynchronous FIFO
  // Xilinx Parameterized Macro, Version 2016.4
  xpm_fifo_async # (
    .FIFO_MEMORY_TYPE          ("auto"),           //string; "auto", "block", "distributed", or "ultra";
    .ECC_MODE                  ("no_ecc"),         //string; "no_ecc" or "en_ecc";
    .RELATED_CLOCKS            (0),                //positive integer; 0 or 1
    .FIFO_WRITE_DEPTH          (LP_WR_FIFO_DEPTH),   //positive integer
    .WRITE_DATA_WIDTH          (C_M00_AXI_DATA_WIDTH),               //positive integer
    .WR_DATA_COUNT_WIDTH       ($clog2(LP_WR_FIFO_DEPTH)),               //positive integer, Not used
    .PROG_FULL_THRESH          (10),               //positive integer, Not used 
    .FULL_RESET_VALUE          (1),                //positive integer; 0 or 1
    .READ_MODE                 ("fwft"),            //string; "std" or "fwft";
    .FIFO_READ_LATENCY         (1),                //positive integer;
    .READ_DATA_WIDTH           (C_M00_AXI_DATA_WIDTH),               //positive integer
    .RD_DATA_COUNT_WIDTH       ($clog2(LP_WR_FIFO_DEPTH)),               //positive integer, not used
    .PROG_EMPTY_THRESH         (10),               //positive integer, not used 
    .DOUT_RESET_VALUE          ("0"),              //string, don't care
    .CDC_SYNC_STAGES           (3),                //positive integer
    .WAKEUP_TIME               (0)                 //positive integer; 0 or 2;
  
  ) inst_wr_xpm_fifo_async (
    .rst           ( ~areset_n_2      ) ,
    .wr_clk        ( ap_clk_2         ) ,
    .wr_en         ( wr_en            ) ,
    .din           ( wr_data          ) ,
    .full          (                  ) ,
    .overflow      (                  ) ,
    .wr_rst_busy   (                  ) ,
    .rd_clk        ( ap_clk           ) ,
    .rd_en         ( wr_fifo_rd_en    ) ,
    .dout          ( wr_fifo_data     ) ,
    .empty         ( wr_fifo_valid_n  ) ,
    .underflow     (                  ) ,
    .rd_rst_busy   (                  ) ,
    .prog_full     (                  ) ,
    .wr_data_count (                  ) ,
    .prog_empty    (                  ) ,
    .rd_data_count (                  ) ,
    .sleep         ( 1'b0             ) ,
    .injectsbiterr ( 1'b0             ) ,
    .injectdbiterr ( 1'b0             ) ,
    .sbiterr       (                  ) ,
    .dbiterr       (                  ) 
  
  );

  ////////////////
  // WRITE CTRL //
  ////////////////

  always_ff@(posedge ap_clk or negedge areset_n)
  begin : write_control
    if(~areset_n) begin
      write_addr_offset <= 0; 
      write_xfer_size_in_bytes <= 0;
      write_burst <= 1'b0;
      wr_vld <= 1'b0;
    end
    else if(!wr_fifo_valid_n) begin
      write_burst <= 1'b1;
      write_addr_offset <= Results;
      write_xfer_size_in_bytes <= LP_RESULTS_BYTES;
      wr_vld <= 1'b1; 
    end
    else if(write_done) begin
      write_burst <= 0;
      wr_vld <= 1'b0;
    end
   end

  always_ff@(posedge ap_clk or negedge areset_n)
  begin : write_starter
    if(~areset_n) begin
      write_start <= 1'b0;
    end
    else
      write_start <= (!wr_fifo_valid_n && !write_burst); 
  end

  assign full_wr_done = (write_done && write_burst);
  assign wr_fifo_rd_en = (wr_rdy && wr_vld);

  // AXI4 Write Master
  AlephMiner_axi_write_master #(
    .C_M_AXI_ADDR_WIDTH  ( C_M00_AXI_ADDR_WIDTH    ) ,
    .C_M_AXI_DATA_WIDTH  ( C_M00_AXI_DATA_WIDTH    ) ,
    .C_XFER_SIZE_WIDTH   ( 32     )
  )
  inst_axi_write_master (
    .aclk                    ( ap_clk                  ) ,
    .areset                  ( areset_n               ) ,
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
    .Data_I                  ( wr_fifo_data            ) ,
    .BVld_O                  ( wr_bvld                 )
  );
 


endmodule : axim_alephminer

