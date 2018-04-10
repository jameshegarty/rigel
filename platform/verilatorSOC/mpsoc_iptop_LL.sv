module IP_Top(
  input         IP_CLK,
  input         IP_ARESET_N,
  input [31:0]  IP_SAXI0_ARADDR,
  input [11:0]  IP_SAXI0_ARID,
  output        IP_SAXI0_ARREADY,
  input         IP_SAXI0_ARVALID,
  input [31:0]  IP_SAXI0_AWADDR,
  input [11:0]  IP_SAXI0_AWID,
  output        IP_SAXI0_AWREADY,
  input         IP_SAXI0_AWVALID,
  output [11:0] IP_SAXI0_BID,
  input         IP_SAXI0_BREADY,
  output [1:0]  IP_SAXI0_BRESP,
  output        IP_SAXI0_BVALID,
  output [31:0] IP_SAXI0_RDATA,
  output [11:0] IP_SAXI0_RID,
  output        IP_SAXI0_RLAST,
  input         IP_SAXI0_RREADY,
  output [1:0]  IP_SAXI0_RRESP,
  output        IP_SAXI0_RVALID,
  input [31:0]  IP_SAXI0_WDATA,
  output        IP_SAXI0_WREADY,
  input [3:0]   IP_SAXI0_WSTRB,
  input         IP_SAXI0_WVALID,

              ///////////////////////////////////////
  output [32:0] IP_MAXI0_ARADDR,
  input         IP_MAXI0_ARADDR_ready,
  input [64:0]  IP_MAXI0_RDATA,
  output        IP_MAXI0_RDATA_ready,
  input [1:0]   IP_MAXI0_RRESP,
  input         IP_MAXI0_RLAST,
  output [3:0]  IP_MAXI0_ARLEN,
  output [1:0]  IP_MAXI0_ARSIZE,
  output [1:0]  IP_MAXI0_ARBURST,
  output [32:0] IP_MAXI0_AWADDR,
  input         IP_MAXI0_AWADDR_ready,
  output [64:0] IP_MAXI0_WDATA,
  input         IP_MAXI0_WDATA_ready,
  output [7:0]  IP_MAXI0_WSTRB,
  output        IP_MAXI0_WLAST,
  input [2:0]   IP_MAXI0_BRESP,
  output        IP_MAXI0_BRESP_ready,
  output [3:0]  IP_MAXI0_AWLEN,
  output [1:0]  IP_MAXI0_AWSIZE,
  output [1:0]  IP_MAXI0_AWBURST,

              ///////////////////////////////////////
  output [32:0] IP_MAXI1_ARADDR,
  input         IP_MAXI1_ARADDR_ready,
  input [64:0]  IP_MAXI1_RDATA,
  output        IP_MAXI1_RDATA_ready,
  input [1:0]   IP_MAXI1_RRESP,
  input         IP_MAXI1_RLAST,
  output [3:0]  IP_MAXI1_ARLEN,
  output [1:0]  IP_MAXI1_ARSIZE,
  output [1:0]  IP_MAXI1_ARBURST,
  output [32:0] IP_MAXI1_AWADDR,
  input         IP_MAXI1_AWADDR_ready,
  output [64:0] IP_MAXI1_WDATA,
  input         IP_MAXI1_WDATA_ready,
  output [7:0]  IP_MAXI1_WSTRB,
  output        IP_MAXI1_WLAST,
  input [2:0]   IP_MAXI1_BRESP,
  output        IP_MAXI1_BRESP_ready,
  output [3:0]  IP_MAXI1_AWLEN,
  output [1:0]  IP_MAXI1_AWSIZE,
  output [1:0]  IP_MAXI1_AWBURST
);

    wire CONFIG_VALID;
//   wire [5*32-1:0] CONFIG_DATA;
   
    wire [31:0] CONFIG_CMD;
    wire [31:0] CONFIG_SRC;
    wire [31:0] CONFIG_DEST;
    wire [31:0] CONFIG_LEN;

//   assign CONFIG_CMD = CONFIG_DATA[31:0];
//   assign CONFIG_SRC = CONFIG_DATA[63:32];
//   assign CONFIG_DEST = CONFIG_DATA[95:64];
//   assign CONFIG_LEN = CONFIG_DATA[127:96];
   
    wire CONFIG_IRQ;
  
    Conf #(.ADDR_BASE(32'hA0000000),.NREG(4))  conf(
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
    .CONFIG_READY(1'b1),
    .CONFIG_CMD(CONFIG_CMD),
    .CONFIG_SRC(CONFIG_SRC),
    .CONFIG_DEST(CONFIG_DEST),
    .CONFIG_LEN(CONFIG_LEN),
    .CONFIG_IRQ(CONFIG_IRQ));

   wire  ip_ready;
   wire  ip_out;
   
   Top top(.CLK(IP_CLK), .ready_downstream(1'b1), .reset(CONFIG_CMD==32'd0), .process_input(CONFIG_VALID && CONFIG_CMD==32'd1), .ready(ip_ready), .process_output(ip_out), .*);
endmodule
