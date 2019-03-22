module VerilatorWrapper(
  input         IP_CLK,
  input         IP_ARESET_N,

    input [31:0]  SAXI0_ARADDR,
    input         SAXI0_ARVALID,
    input         SAXI0_ARLAST,
    input  [1:0]  SAXI0_ARBURST,
    input  [3:0]  SAXI0_ARLEN,
    input  [2:0]  SAXI0_ARPROT,
    input   [1:0] SAXI0_ARSIZE,
    input   [3:0] SAXI0_ARCACHE,
    input         SAXI0_ARLOCK,
    output        SAXI0_ARREADY,
    input [11:0]  SAXI0_ARID,
    input [31:0]  SAXI0_AWADDR,
    input         SAXI0_AWVALID,
    input   [1:0] SAXI0_AWSIZE,
    input   [3:0] SAXI0_AWLEN,
    input   [1:0] SAXI0_AWBURST,
    output        SAXI0_AWREADY,
    input [11:0]  SAXI0_AWID,
    output [1:0]  SAXI0_BRESP,
    output        SAXI0_BVALID,
    input         SAXI0_BREADY,
    output [11:0] SAXI0_BID,
    output [31:0] SAXI0_RDATA,
    output        SAXI0_RVALID,
    input         SAXI0_RREADY, 
    output [11:0] SAXI0_RID,
    output        SAXI0_RLAST,
    input [31:0]  SAXI0_WDATA,
    input         SAXI0_WVALID,
    input         SAXI0_WLAST,
    input [11:0]  SAXI0_WID,
    output        SAXI0_WREADY,
    output [1:0]  SAXI0_RRESP,
    input [3:0]   SAXI0_WSTRB,


    output [31:0] MAXI0_ARADDR,
    output        MAXI0_ARVALID,
    input         MAXI0_ARREADY,
    input [63:0]  MAXI0_RDATA,
    input [11:0]  MAXI0_RID,
    output [2:0]  MAXI0_ARPROT,
    output [11:0] MAXI0_ARID,
    output [3:0] MAXI0_ARCACHE,
    output  MAXI0_ARLOCK,
    input         MAXI0_RVALID,
    output        MAXI0_RREADY,
    input [1:0]   MAXI0_RRESP,
    input         MAXI0_RLAST,
    output [3:0]  MAXI0_ARLEN,
    output [1:0]  MAXI0_ARSIZE,
    output [1:0]  MAXI0_ARBURST,

    output [31:0] MAXI0_AWADDR,
    output        MAXI0_AWVALID,
    input         MAXI0_AWREADY,
    output [11:0] MAXI0_AWID,
    output [11:0] MAXI0_WID,
    input [11:0]  MAXI0_BID,
    output [63:0] MAXI0_WDATA,
    output        MAXI0_WVALID,
    input         MAXI0_WREADY,
    input [1:0]   MAXI0_BRESP,
    input         MAXI0_BVALID,
    output        MAXI0_BREADY,
    output [7:0]  MAXI0_WSTRB,
    output        MAXI0_WLAST,
    output [3:0]  MAXI0_AWLEN,
    output [1:0]  MAXI0_AWSIZE,
    output [1:0]  MAXI0_AWBURST,

    output [31:0] MAXI1_ARADDR,
    output        MAXI1_ARVALID,
    input         MAXI1_ARREADY,
    input [63:0]  MAXI1_RDATA,
    input [11:0]  MAXI1_RID,
    output [2:0]  MAXI1_ARPROT,
    output [11:0] MAXI1_ARID,
    output [3:0] MAXI1_ARCACHE,
    output MAXI1_ARLOCK,
    input         MAXI1_RVALID,
    output        MAXI1_RREADY,
    input [1:0]   MAXI1_RRESP,
    input         MAXI1_RLAST,
    output [3:0]  MAXI1_ARLEN,
    output [1:0]  MAXI1_ARSIZE,
    output [1:0]  MAXI1_ARBURST,

    output [31:0] MAXI1_AWADDR,
    output        MAXI1_AWVALID,
    input         MAXI1_AWREADY,
    output [63:0] MAXI1_WDATA,
    output        MAXI1_WVALID,
    input         MAXI1_WREADY,
    input [1:0]   MAXI1_BRESP,
    input         MAXI1_BVALID,
    output        MAXI1_BREADY,
    output [7:0]  MAXI1_WSTRB,
    output        MAXI1_WLAST,
    output [3:0]  MAXI1_AWLEN,
    output [1:0]  MAXI1_AWSIZE,
    output [1:0]  MAXI1_AWBURST
);

   wire [138:0] ZynqNOC_write_input; // write issue
   assign MAXI0_WDATA = ZynqNOC_write_input[116:53];
assign MAXI0_AWBURST = ZynqNOC_write_input[37:36];
assign MAXI0_WLAST = ZynqNOC_write_input[125:125];
assign MAXI0_AWID = ZynqNOC_write_input[51:40];
assign MAXI0_AWSIZE = ZynqNOC_write_input[39:38];
assign MAXI0_AWADDR = ZynqNOC_write_input[31:0];
assign MAXI0_AWVALID = ZynqNOC_write_input[52];
assign MAXI0_WID = ZynqNOC_write_input[137:126];
assign MAXI0_WSTRB = ZynqNOC_write_input[124:117];
assign MAXI0_WVALID = ZynqNOC_write_input[138];
assign MAXI0_AWLEN = ZynqNOC_write_input[35:32];
   wire [14:0]  ZynqNOC_write; // write response
   assign ZynqNOC_write = {MAXI0_BVALID,MAXI0_BID,MAXI0_BRESP};
   wire         ZynqNOC_readSink_ready;
   assign ZynqNOC_readSink_ready = SAXI0_RREADY;
   wire         ZynqNOC_readSource_ready_downstream;
   assign SAXI0_ARREADY = ZynqNOC_readSource_ready_downstream;
   wire         ZynqNOC_writeSink_ready;
   assign ZynqNOC_writeSink_ready= SAXI0_BREADY;
   wire ZynqNOC_write_ready_downstream;  
   assign MAXI0_BREADY = ZynqNOC_write_ready_downstream;
   wire [1:0] ZynqNOC_write_ready;  
   assign ZynqNOC_write_ready = {MAXI0_WREADY,MAXI0_AWREADY};  
   wire [1:0] ZynqNOC_writeSource_ready_downstream; 
   //assign ZynqNOC_writeSource_ready_downstream = {SAXI0_WREADY,SAXI0_AWREADY};
   assign SAXI0_AWREADY = ZynqNOC_writeSource_ready_downstream[0];
   assign SAXI0_WREADY = ZynqNOC_writeSource_ready_downstream[1];
   wire [102:0] ZynqNOC_writeSource;  // issue write to slave
   assign ZynqNOC_writeSource[52:0] = {SAXI0_AWVALID,SAXI0_AWID,SAXI0_AWSIZE,SAXI0_AWBURST,SAXI0_AWLEN,SAXI0_AWADDR};
   assign ZynqNOC_writeSource[102:53] = {SAXI0_WVALID,SAXI0_WID,SAXI0_WLAST,SAXI0_WSTRB,SAXI0_WDATA};
   wire [14:0] ZynqNOC_writeSink_input; // return write result from slave
   assign SAXI0_BVALID = ZynqNOC_writeSink_input[14];
assign SAXI0_BID = ZynqNOC_writeSink_input[13:2];
assign SAXI0_BRESP = ZynqNOC_writeSink_input[1:0];
   wire [60:0] ZynqNOC_readSource;  // issue read to slave
   assign ZynqNOC_readSource = {SAXI0_ARVALID,SAXI0_ARLOCK,SAXI0_ARCACHE,SAXI0_ARPROT,SAXI0_ARID,SAXI0_ARBURST,SAXI0_ARSIZE,SAXI0_ARLEN,SAXI0_ARADDR};
   wire [47:0] ZynqNOC_readSink_input;  // slave read response
   assign SAXI0_RVALID = ZynqNOC_readSink_input[47];
assign SAXI0_RLAST = ZynqNOC_readSink_input[32:32];
assign SAXI0_RDATA = ZynqNOC_readSink_input[31:0];
assign SAXI0_RRESP = ZynqNOC_readSink_input[34:33];
assign SAXI0_RID = ZynqNOC_readSink_input[46:35];

   wire         ZynqNOC_read_ready_downstream;
   assign MAXI0_RREADY = ZynqNOC_read_ready_downstream;
   wire   ZynqNOC_read_ready;
   assign ZynqNOC_read_ready = MAXI0_ARREADY;
   wire [60:0] ZynqNOC_read_input; // read request
   assign MAXI0_ARADDR = ZynqNOC_read_input[31:0];
assign MAXI0_ARVALID = ZynqNOC_read_input[60];
assign MAXI0_ARCACHE = ZynqNOC_read_input[58:55];
assign MAXI0_ARLEN = ZynqNOC_read_input[35:32];
assign MAXI0_ARLOCK = ZynqNOC_read_input[59:59];
assign MAXI0_ARSIZE = ZynqNOC_read_input[37:36];
assign MAXI0_ARID = ZynqNOC_read_input[51:40];
assign MAXI0_ARPROT = ZynqNOC_read_input[54:52];
assign MAXI0_ARBURST = ZynqNOC_read_input[39:38];
   wire [79:0] ZynqNOC_read;    // read response
   assign ZynqNOC_read = {MAXI0_RVALID,MAXI0_RID,MAXI0_RRESP,MAXI0_RLAST,MAXI0_RDATA};
wire         ZynqNOC_read1_ready_downstream;
   assign MAXI1_RREADY = ZynqNOC_read1_ready_downstream;
   wire   ZynqNOC_read1_ready;
   assign ZynqNOC_read1_ready = MAXI1_ARREADY;
   wire [60:0] ZynqNOC_read1_input; // read request
   assign MAXI1_ARADDR = ZynqNOC_read1_input[31:0];
assign MAXI1_ARVALID = ZynqNOC_read1_input[60];
assign MAXI1_ARCACHE = ZynqNOC_read1_input[58:55];
assign MAXI1_ARLEN = ZynqNOC_read1_input[35:32];
assign MAXI1_ARLOCK = ZynqNOC_read1_input[59:59];
assign MAXI1_ARSIZE = ZynqNOC_read1_input[37:36];
assign MAXI1_ARID = ZynqNOC_read1_input[51:40];
assign MAXI1_ARPROT = ZynqNOC_read1_input[54:52];
assign MAXI1_ARBURST = ZynqNOC_read1_input[39:38];
   wire [79:0] ZynqNOC_read1;    // read response
   assign ZynqNOC_read1 = {MAXI1_RVALID,MAXI1_RID,MAXI1_RRESP,MAXI1_RLAST,MAXI1_RDATA};

   Top top(.CLK(IP_CLK), .reset(~IP_ARESET_N), .*);

endmodule
