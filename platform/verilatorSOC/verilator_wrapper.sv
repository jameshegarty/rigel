module VerilatorWrapper(
  input         IP_CLK,
  input         IP_ARESET_N,

input [31:0] SAXI0_ARADDR,
input [2:0] SAXI0_ARPROT,
input [3:0] SAXI0_ARCACHE,
input [7:0] SAXI0_ARLEN,
input [3:0] SAXI0_ARQOS,
input [0:0] SAXI0_ARLOCK,
input [5:0] SAXI0_ARUSER,
input [3:0] SAXI0_ARREGION,
input [11:0] SAXI0_ARID,
input [2:0] SAXI0_ARSIZE,
input [1:0] SAXI0_ARBURST,
input SAXI0_ARVALID,
output SAXI0_ARREADY,
output [1:0] SAXI0_RRESP,
output [0:0] SAXI0_RLAST,
output [31:0] SAXI0_RDATA,
output [5:0] SAXI0_RUSER,
output [11:0] SAXI0_RID,
output SAXI0_RVALID,
input SAXI0_RREADY,
input [1:0] SAXI0_AWBURST,
input [0:0] SAXI0_AWLOCK,
input [3:0] SAXI0_AWCACHE,
input [2:0] SAXI0_AWSIZE,
input [3:0] SAXI0_AWQOS,
input [31:0] SAXI0_AWADDR,
input [7:0] SAXI0_AWLEN,
input [5:0] SAXI0_AWUSER,
input [11:0] SAXI0_AWID,
input [2:0] SAXI0_AWPROT,
input [3:0] SAXI0_AWREGION,
output SAXI0_AWREADY,
input SAXI0_AWVALID,
input [31:0] SAXI0_WDATA,
input [3:0] SAXI0_WSTRB,
input [0:0] SAXI0_WLAST,
input [5:0] SAXI0_WUSER,
output SAXI0_WREADY,
input SAXI0_WVALID,
output [11:0] SAXI0_BID,
output [5:0] SAXI0_BUSER,
output [1:0] SAXI0_BRESP,
input SAXI0_BREADY,
output SAXI0_BVALID,
output [31:0] MAXI0_ARADDR,
output [2:0] MAXI0_ARPROT,
output [3:0] MAXI0_ARCACHE,
output [7:0] MAXI0_ARLEN,
output [3:0] MAXI0_ARQOS,
output [0:0] MAXI0_ARLOCK,
output [5:0] MAXI0_ARUSER,
output [3:0] MAXI0_ARREGION,
output [11:0] MAXI0_ARID,
output [2:0] MAXI0_ARSIZE,
output [1:0] MAXI0_ARBURST,
output MAXI0_ARVALID,
input MAXI0_ARREADY,
input [1:0] MAXI0_RRESP,
input [0:0] MAXI0_RLAST,
input [63:0] MAXI0_RDATA,
input [5:0] MAXI0_RUSER,
input [11:0] MAXI0_RID,
input MAXI0_RVALID,
output MAXI0_RREADY,
output [1:0] MAXI0_AWBURST,
output [0:0] MAXI0_AWLOCK,
output [3:0] MAXI0_AWCACHE,
output [2:0] MAXI0_AWSIZE,
output [3:0] MAXI0_AWQOS,
output [31:0] MAXI0_AWADDR,
output [7:0] MAXI0_AWLEN,
output [5:0] MAXI0_AWUSER,
output [11:0] MAXI0_AWID,
output [2:0] MAXI0_AWPROT,
output [3:0] MAXI0_AWREGION,
input MAXI0_AWREADY,
output MAXI0_AWVALID,
output [63:0] MAXI0_WDATA,
output [7:0] MAXI0_WSTRB,
output [0:0] MAXI0_WLAST,
output [5:0] MAXI0_WUSER,
input MAXI0_WREADY,
output MAXI0_WVALID,
input [11:0] MAXI0_BID,
input [5:0] MAXI0_BUSER,
input [1:0] MAXI0_BRESP,
output MAXI0_BREADY,
input MAXI0_BVALID,
output [31:0] MAXI1_ARADDR,
output [2:0] MAXI1_ARPROT,
output [3:0] MAXI1_ARCACHE,
output [7:0] MAXI1_ARLEN,
output [3:0] MAXI1_ARQOS,
output [0:0] MAXI1_ARLOCK,
output [5:0] MAXI1_ARUSER,
output [3:0] MAXI1_ARREGION,
output [11:0] MAXI1_ARID,
output [2:0] MAXI1_ARSIZE,
output [1:0] MAXI1_ARBURST,
output MAXI1_ARVALID,
input MAXI1_ARREADY,
input [1:0] MAXI1_RRESP,
input [0:0] MAXI1_RLAST,
input [63:0] MAXI1_RDATA,
input [5:0] MAXI1_RUSER,
input [11:0] MAXI1_RID,
input MAXI1_RVALID,
output MAXI1_RREADY,
output [1:0] MAXI1_AWBURST,
output [0:0] MAXI1_AWLOCK,
output [3:0] MAXI1_AWCACHE,
output [2:0] MAXI1_AWSIZE,
output [3:0] MAXI1_AWQOS,
output [31:0] MAXI1_AWADDR,
output [7:0] MAXI1_AWLEN,
output [5:0] MAXI1_AWUSER,
output [11:0] MAXI1_AWID,
output [2:0] MAXI1_AWPROT,
output [3:0] MAXI1_AWREGION,
input MAXI1_AWREADY,
output MAXI1_AWVALID,
output [63:0] MAXI1_WDATA,
output [7:0] MAXI1_WSTRB,
output [0:0] MAXI1_WLAST,
output [5:0] MAXI1_WUSER,
input MAXI1_WREADY,
output MAXI1_WVALID,
input [11:0] MAXI1_BID,
input [5:0] MAXI1_BUSER,
input [1:0] MAXI1_BRESP,
output MAXI1_BREADY,
input MAXI1_BVALID);

   wire [159:0] ZynqNOC_write_input; // write issue
   assign MAXI0_WUSER = ZynqNOC_write_input[158:153];
assign MAXI0_AWQOS = ZynqNOC_write_input[77:74];
assign MAXI0_WLAST = ZynqNOC_write_input[152:152];
assign MAXI0_AWCACHE = ZynqNOC_write_input[60:57];
assign MAXI0_AWLOCK = ZynqNOC_write_input[78:78];
assign MAXI0_AWUSER = ZynqNOC_write_input[73:68];
assign MAXI0_WDATA = ZynqNOC_write_input[143:80];
assign MAXI0_WSTRB = ZynqNOC_write_input[151:144];
assign MAXI0_AWID = ZynqNOC_write_input[56:45];
assign MAXI0_AWREGION = ZynqNOC_write_input[67:64];
assign MAXI0_AWSIZE = ZynqNOC_write_input[44:42];
assign MAXI0_AWADDR = ZynqNOC_write_input[31:0];
assign MAXI0_AWVALID = ZynqNOC_write_input[79];
assign MAXI0_AWLEN = ZynqNOC_write_input[39:32];
assign MAXI0_AWBURST = ZynqNOC_write_input[41:40];
assign MAXI0_WVALID = ZynqNOC_write_input[159];
assign MAXI0_AWPROT = ZynqNOC_write_input[63:61];
   wire [20:0]  ZynqNOC_write_output; // write response
   assign ZynqNOC_write_output = {MAXI0_BVALID,MAXI0_BUSER,MAXI0_BID,MAXI0_BRESP};
   wire ZynqNOC_write_ready_downstream;  
   assign MAXI0_BREADY = ZynqNOC_write_ready_downstream;
   wire [1:0] ZynqNOC_write_ready;  
   assign ZynqNOC_write_ready = {MAXI0_WREADY,MAXI0_AWREADY};  

   ////////////////
   wire         regs_read_ready_downstream;
   assign regs_read_ready_downstream = SAXI0_RREADY;
   wire         regs_read_ready;
   assign SAXI0_ARREADY = regs_read_ready;
   wire [79:0] regs_read_input;  // issue read to slave
   assign regs_read_input = {SAXI0_ARVALID,SAXI0_ARQOS,SAXI0_ARUSER,SAXI0_ARREGION,SAXI0_ARLOCK,SAXI0_ARCACHE,SAXI0_ARPROT,SAXI0_ARID,SAXI0_ARBURST,SAXI0_ARSIZE,SAXI0_ARLEN,SAXI0_ARADDR};
   wire [53:0] regs_read_output;  // slave read response
   assign SAXI0_RVALID = regs_read_output[53];
assign SAXI0_RLAST = regs_read_output[32:32];
assign SAXI0_RID = regs_read_output[46:35];
assign SAXI0_RDATA = regs_read_output[31:0];
assign SAXI0_RUSER = regs_read_output[52:47];
assign SAXI0_RRESP = regs_read_output[34:33];

   wire         regs_write_ready_downstream;
   assign regs_write_ready_downstream = SAXI0_BREADY;
   wire [1:0] regs_write_ready; 
   assign SAXI0_AWREADY = regs_write_ready[0];
   assign SAXI0_WREADY = regs_write_ready[1];
   wire [123:0] regs_write_input;  // issue write to slave
   assign regs_write_input[79:0] = {SAXI0_AWVALID,SAXI0_AWLOCK,SAXI0_AWQOS,SAXI0_AWUSER,SAXI0_AWREGION,SAXI0_AWPROT,SAXI0_AWCACHE,SAXI0_AWID,SAXI0_AWSIZE,SAXI0_AWBURST,SAXI0_AWLEN,SAXI0_AWADDR};
   assign regs_write_input[123:80] = {SAXI0_WVALID,SAXI0_WUSER,SAXI0_WLAST,SAXI0_WSTRB,SAXI0_WDATA};
   wire [20:0] regs_write_output; // return write result from slave
   assign SAXI0_BVALID = regs_write_output[20];
assign SAXI0_BID = regs_write_output[13:2];
assign SAXI0_BUSER = regs_write_output[19:14];
assign SAXI0_BRESP = regs_write_output[1:0];
   /////////////////////

   wire         ZynqNOC_read_ready_downstream;
   assign MAXI0_RREADY = ZynqNOC_read_ready_downstream;
   wire   ZynqNOC_read_ready;
   assign ZynqNOC_read_ready = MAXI0_ARREADY;
   wire [79:0] ZynqNOC_read_input; // read request
   assign MAXI0_ARADDR = ZynqNOC_read_input[31:0];
assign MAXI0_ARPROT = ZynqNOC_read_input[59:57];
assign MAXI0_ARCACHE = ZynqNOC_read_input[63:60];
assign MAXI0_ARBURST = ZynqNOC_read_input[44:43];
assign MAXI0_ARLEN = ZynqNOC_read_input[39:32];
assign MAXI0_ARSIZE = ZynqNOC_read_input[42:40];
assign MAXI0_ARLOCK = ZynqNOC_read_input[64:64];
assign MAXI0_ARVALID = ZynqNOC_read_input[79];
assign MAXI0_ARREGION = ZynqNOC_read_input[68:65];
assign MAXI0_ARID = ZynqNOC_read_input[56:45];
assign MAXI0_ARQOS = ZynqNOC_read_input[78:75];
assign MAXI0_ARUSER = ZynqNOC_read_input[74:69];
   wire [85:0] ZynqNOC_read_output;    // read response
   assign ZynqNOC_read_output = {MAXI0_RVALID,MAXI0_RUSER,MAXI0_RID,MAXI0_RRESP,MAXI0_RLAST,MAXI0_RDATA};
wire         ZynqNOC_read1_ready_downstream;
   assign MAXI1_RREADY = ZynqNOC_read1_ready_downstream;
   wire   ZynqNOC_read1_ready;
   assign ZynqNOC_read1_ready = MAXI1_ARREADY;
   wire [79:0] ZynqNOC_read1_input; // read request
   assign MAXI1_ARADDR = ZynqNOC_read1_input[31:0];
assign MAXI1_ARPROT = ZynqNOC_read1_input[59:57];
assign MAXI1_ARCACHE = ZynqNOC_read1_input[63:60];
assign MAXI1_ARBURST = ZynqNOC_read1_input[44:43];
assign MAXI1_ARLEN = ZynqNOC_read1_input[39:32];
assign MAXI1_ARSIZE = ZynqNOC_read1_input[42:40];
assign MAXI1_ARLOCK = ZynqNOC_read1_input[64:64];
assign MAXI1_ARVALID = ZynqNOC_read1_input[79];
assign MAXI1_ARREGION = ZynqNOC_read1_input[68:65];
assign MAXI1_ARID = ZynqNOC_read1_input[56:45];
assign MAXI1_ARQOS = ZynqNOC_read1_input[78:75];
assign MAXI1_ARUSER = ZynqNOC_read1_input[74:69];
   wire [85:0] ZynqNOC_read1_output;    // read response
   assign ZynqNOC_read1_output = {MAXI1_RVALID,MAXI1_RUSER,MAXI1_RID,MAXI1_RRESP,MAXI1_RLAST,MAXI1_RDATA};

   Top top(.CLK(IP_CLK), .reset(~IP_ARESET_N), .*);

endmodule
