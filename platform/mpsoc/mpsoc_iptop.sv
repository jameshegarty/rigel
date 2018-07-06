module IP_Top(
  input wire         IP_CLK,
  input wire         IP_ARESET_N,
  input wire [31:0]  IP_SAXI0_ARADDR,
  input wire [11:0]  IP_SAXI0_ARID,
  output wire        IP_SAXI0_ARREADY,
  input wire         IP_SAXI0_ARVALID,
  input wire [31:0]  IP_SAXI0_AWADDR,
  input wire [11:0]  IP_SAXI0_AWID,
  output wire        IP_SAXI0_AWREADY,
  input wire         IP_SAXI0_AWVALID,
  output wire [11:0] IP_SAXI0_BID,
  input wire         IP_SAXI0_BREADY,
  output wire [1:0]  IP_SAXI0_BRESP,
  output wire        IP_SAXI0_BVALID,
  output wire [31:0] IP_SAXI0_RDATA,
  output wire [11:0] IP_SAXI0_RID,
  output wire        IP_SAXI0_RLAST,
  input wire         IP_SAXI0_RREADY,
  output wire [1:0]  IP_SAXI0_RRESP,
  output wire        IP_SAXI0_RVALID,
  input wire [31:0]  IP_SAXI0_WDATA,
  output wire        IP_SAXI0_WREADY,
  input wire [3:0]   IP_SAXI0_WSTRB,
  input wire         IP_SAXI0_WVALID,

  output wire [31:0] IP_MAXI0_ARADDR,
  input wire         IP_MAXI0_ARREADY,
  output wire        IP_MAXI0_ARVALID,
  input wire [63:0]  IP_MAXI0_RDATA,
  output wire        IP_MAXI0_RREADY,
  input wire [1:0]   IP_MAXI0_RRESP,
  input wire         IP_MAXI0_RVALID,
  input wire         IP_MAXI0_RLAST,
  output wire [3:0]  IP_MAXI0_ARLEN,
  output wire [1:0]  IP_MAXI0_ARSIZE,
  output wire [1:0]  IP_MAXI0_ARBURST,
  output wire [31:0] IP_MAXI0_AWADDR,
  input wire         IP_MAXI0_AWREADY,
  output wire        IP_MAXI0_AWVALID,
  output wire [63:0] IP_MAXI0_WDATA,
  output wire [7:0]  IP_MAXI0_WSTRB,
  input wire         IP_MAXI0_WREADY,
  output wire        IP_MAXI0_WVALID,
  output wire        IP_MAXI0_WLAST,
  input wire [1:0]   IP_MAXI0_BRESP,
  input wire         IP_MAXI0_BVALID,
  output wire        IP_MAXI0_BREADY,
  output wire [3:0]  IP_MAXI0_AWLEN,
  output wire [1:0]  IP_MAXI0_AWSIZE,
  output wire [1:0]  IP_MAXI0_AWBURST
);

    wire CONFIG_VALID;
   wire [___CONF_NREG*32-1:0] CONFIG_DATA;
   
    wire [31:0] CONFIG_CMD;
    wire [31:0] CONFIG_SRC;
    wire [31:0] CONFIG_DEST;
    wire [31:0] CONFIG_LEN;

   assign CONFIG_CMD = CONFIG_DATA[31:0];
   assign CONFIG_SRC = CONFIG_DATA[63:32];
   assign CONFIG_DEST = CONFIG_DATA[95:64];
   assign CONFIG_LEN = CONFIG_DATA[127:96];
   
    wire CONFIG_IRQ;
  
    wire READER_READY;
    wire WRITER_READY;

   wire  CONFIG_READY;
    assign CONFIG_READY = READER_READY && WRITER_READY;
    
    Conf #(.ADDR_BASE(32'hA0000000),.NREG(___CONF_NREG))  conf(
    .ACLK(IP_CLK),
    .ARESETN(IP_ARESET_N),
    .S_AXI_ARADDR(IP_SAXI0_ARADDR), 
    .S_AXI_ARID(IP_SAXI0_ARID),  
    .S_AXI_ARREADY(IP_SAXI0_ARREADY), 
    .S_AXI_ARVALID(IP_SAXI0_ARVALID), 
    .S_AXI_AWADDR(IP_SAXI0_AWADDR), 
    .S_AXI_AWID(IP_SAXI0_AWID), 
    .S_AXI_AWREADY(IP_SAXI0_AWREADY), 
    .S_AXI_AWVALID(IP_SAXI0_AWVALID), 
    .S_AXI_BID(IP_SAXI0_BID), 
    .S_AXI_BREADY(IP_SAXI0_BREADY), 
    .S_AXI_BRESP(IP_SAXI0_BRESP), 
    .S_AXI_BVALID(IP_SAXI0_BVALID), 
    .S_AXI_RDATA(IP_SAXI0_RDATA), 
    .S_AXI_RID(IP_SAXI0_RID), 
    .S_AXI_RLAST(IP_SAXI0_RLAST), 
    .S_AXI_RREADY(IP_SAXI0_RREADY), 
    .S_AXI_RRESP(IP_SAXI0_RRESP), 
    .S_AXI_RVALID(IP_SAXI0_RVALID), 
    .S_AXI_WDATA(IP_SAXI0_WDATA), 
    .S_AXI_WREADY(IP_SAXI0_WREADY), 
    .S_AXI_WSTRB(IP_SAXI0_WSTRB), 
    .S_AXI_WVALID(IP_SAXI0_WVALID),
    .CONFIG_VALID(CONFIG_VALID),
    .CONFIG_READY(CONFIG_READY),
    .CONFIG_DATA(CONFIG_DATA),                                           
    .CONFIG_IRQ(CONFIG_IRQ));

   // lengthInput/lengthOutput are in bytes
   wire [31:0] lengthInput;
   assign lengthInput = {4'b0000,CONFIG_LEN[27:0]};
   wire [31:0] lengthOutput;
   assign lengthOutput = (CONFIG_LEN[27:0] << 8'd8) >> CONFIG_LEN[31:28];

  wire [63:0] pipelineInput;
  wire       pipelineInputValid;
   
  wire [64:0] pipelineOutputPacked;
  wire [63:0] pipelineOutput;
  assign pipelineOutput = pipelineOutputPacked[63:0];   
  wire pipelineOutputValid;
  assign pipelineOutputValid = pipelineOutputPacked[64];
   
  wire       pipelineReady;
  wire      downstreamReady;

  ___PIPELINE_MODULE_NAME pipeline(.CLK(IP_CLK),.reset(CONFIG_READY),.ready(pipelineReady),.ready_downstream(downstreamReady),.process_input({pipelineInputValid,pipelineInput}),.process_output(pipelineOutputPacked) ___PIPELINE_TAPINPUT );

  DRAMReader reader(
    .ACLK(IP_CLK),
    .ARESETN(IP_ARESET_N),
    .M_AXI_ARADDR(IP_MAXI0_ARADDR),
    .M_AXI_ARREADY(IP_MAXI0_ARREADY),
    .M_AXI_ARVALID(IP_MAXI0_ARVALID),
    .M_AXI_RDATA(IP_MAXI0_RDATA),
    .M_AXI_RREADY(IP_MAXI0_RREADY),
    .M_AXI_RRESP(IP_MAXI0_RRESP),
    .M_AXI_RVALID(IP_MAXI0_RVALID),
    .M_AXI_RLAST(IP_MAXI0_RLAST),
    .M_AXI_ARLEN(IP_MAXI0_ARLEN),
    .M_AXI_ARSIZE(IP_MAXI0_ARSIZE),
    .M_AXI_ARBURST(IP_MAXI0_ARBURST),
    
    .CONFIG_VALID(CONFIG_VALID),
    .CONFIG_READY(READER_READY),
    .CONFIG_START_ADDR(CONFIG_SRC),
    .CONFIG_NBYTES(___PIPELINE_INPUT_BYTES),

    .DATA_READY_DOWNSTREAM(pipelineReady),
    .DATA_VALID(pipelineInputValid),
    .DATA(pipelineInput)
  );
  
  DRAMWriter writer(
    .ACLK(IP_CLK),
    .ARESETN(IP_ARESET_N),
    .M_AXI_AWADDR(IP_MAXI0_AWADDR),
    .M_AXI_AWREADY(IP_MAXI0_AWREADY),
    .M_AXI_AWVALID(IP_MAXI0_AWVALID),
    .M_AXI_WDATA(IP_MAXI0_WDATA),
    .M_AXI_WREADY(IP_MAXI0_WREADY),
    .M_AXI_WVALID(IP_MAXI0_WVALID),
    .M_AXI_WLAST(IP_MAXI0_WLAST),
    .M_AXI_WSTRB(IP_MAXI0_WSTRB),
    
    .M_AXI_BRESP(IP_MAXI0_BRESP),
    .M_AXI_BREADY(IP_MAXI0_BREADY),
    .M_AXI_BVALID(IP_MAXI0_BVALID),
    
    .M_AXI_AWLEN(IP_MAXI0_AWLEN),
    .M_AXI_AWSIZE(IP_MAXI0_AWSIZE),
    .M_AXI_AWBURST(IP_MAXI0_AWBURST),
    
    .CONFIG_VALID(CONFIG_VALID),
    .CONFIG_READY(WRITER_READY),
    .CONFIG_START_ADDR(CONFIG_DEST),
    .CONFIG_NBYTES(___PIPELINE_OUTPUT_BYTES),

    .DATA_READY(downstreamReady),
    .DATA_VALID(pipelineOutputValid),
    .DATA(pipelineOutput)
  );

endmodule
