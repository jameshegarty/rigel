module VerilatorWrapper(
    input         IP_CLK,
    input         IP_ARESET_N,
    //AXI Inputs
    input [31:0]  SAXI0_ARADDR,
    input         SAXI0_ARVALID,
    output        SAXI0_ARREADY,
    input [11:0]  SAXI0_ARID,
    input [31:0]  SAXI0_AWADDR,
    input         SAXI0_AWVALID,
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
    output        SAXI0_WREADY,
    output [1:0]  SAXI0_RRESP,
    input [3:0]   SAXI0_WSTRB,


    output [31:0] MAXI0_ARADDR,
    output        MAXI0_ARVALID,
    input         MAXI0_ARREADY,
    input [63:0]  MAXI0_RDATA,
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
    output [1:0]  MAXI0_AWBURST
);

   wire [31:0]   IP_SAXI0_ARADDR;
   assign IP_SAXI0_ARADDR = SAXI0_ARADDR;
   wire          IP_SAXI0_ARREADY;
   assign SAXI0_ARREADY = IP_SAXI0_ARREADY;
   wire          IP_SAXI0_ARVALID;
   assign IP_SAXI0_ARVALID = SAXI0_ARVALID;
   wire [11:0]   IP_SAXI0_ARID;
   assign IP_SAXI0_ARID = SAXI0_ARID;
   wire [31:0]   IP_SAXI0_AWADDR;
   assign IP_SAXI0_AWADDR = SAXI0_AWADDR;
   wire          IP_SAXI0_AWREADY;
   assign SAXI0_AWREADY = IP_SAXI0_AWREADY;
   wire          IP_SAXI0_AWVALID;
   assign IP_SAXI0_AWVALID = SAXI0_AWVALID;
   wire [11:0]   IP_SAXI0_AWID;
   assign IP_SAXI0_AWID = SAXI0_AWID;
   wire [11:0]   IP_SAXI0_BID;
   assign SAXI0_BID = IP_SAXI0_BID;
   wire          IP_SAXI0_BREADY;
   assign IP_SAXI0_BREADY = SAXI0_BREADY;
   wire          IP_SAXI0_BVALID;
   assign SAXI0_BVALID = IP_SAXI0_BVALID;
   wire [31:0]   IP_SAXI0_RDATA;
   assign SAXI0_RDATA = IP_SAXI0_RDATA;
   wire [1:0]    IP_SAXI0_BRESP;
   assign SAXI0_BRESP = IP_SAXI0_BRESP;
   wire [11:0]   IP_SAXI0_RID;
   assign SAXI0_RID = IP_SAXI0_RID;
   wire          IP_SAXI0_RLAST;
   assign SAXI0_RLAST = IP_SAXI0_RLAST;
   wire          IP_SAXI0_RREADY;
   assign IP_SAXI0_RREADY = SAXI0_RREADY;
   wire          IP_SAXI0_RVALID;
   assign SAXI0_RVALID = IP_SAXI0_RVALID;
   wire [31:0]   IP_SAXI0_WDATA;
   assign IP_SAXI0_WDATA = SAXI0_WDATA;
   wire [1:0]    IP_SAXI0_RRESP;
   assign SAXI0_RRESP = IP_SAXI0_RRESP;
   wire          IP_SAXI0_WREADY;
   assign SAXI0_WREADY = IP_SAXI0_WREADY;
   wire [3:0]    IP_SAXI0_WSTRB;
   assign IP_SAXI0_WSTRB = SAXI0_WSTRB;
   wire          IP_SAXI0_WVALID;
   assign IP_SAXI0_WVALID = SAXI0_WVALID;


   wire [32:0] IP_MAXI0_ARADDR;
   wire IP_MAXI0_ARADDR_ready;
   assign     MAXI0_ARADDR = IP_MAXI0_ARADDR[31:0];
   assign     MAXI0_ARVALID = IP_MAXI0_ARADDR[32];
   assign IP_MAXI0_ARADDR_ready = MAXI0_ARREADY;
   
   wire [64:0] IP_MAXI0_RDATA;
   wire        IP_MAXI0_RDATA_ready;
   assign IP_MAXI0_RDATA = {MAXI0_RVALID,MAXI0_RDATA};
   assign MAXI0_RREADY = IP_MAXI0_RDATA_ready;
   
   wire [1:0]    IP_MAXI0_RRESP;
   assign IP_MAXI0_RRESP = MAXI0_RRESP;
   wire          IP_MAXI0_RLAST;
   assign IP_MAXI0_RLAST = MAXI0_RLAST;
   wire [3:0]    IP_MAXI0_ARLEN;
   assign MAXI0_ARLEN = IP_MAXI0_ARLEN;
   wire [1:0]    IP_MAXI0_ARSIZE;
   assign MAXI0_ARSIZE = IP_MAXI0_ARSIZE;
   wire [1:0]    IP_MAXI0_ARBURST;
   assign MAXI0_ARBURST = IP_MAXI0_ARBURST;

   wire [32:0]   IP_MAXI0_AWADDR;
   wire          IP_MAXI0_AWADDR_ready;
   //input         IP_MAXI0_AWREADY;
   //output        IP_MAXI0_AWVALID;
   assign MAXI0_AWADDR = IP_MAXI0_AWADDR[31:0];
   assign MAXI0_AWVALID = IP_MAXI0_AWADDR[32];
   assign IP_MAXI0_AWADDR_ready =MAXI0_AWREADY;
  
   wire [64:0]   IP_MAXI0_WDATA;
   wire          IP_MAXI0_WDATA_ready;
    //input         IP_MAXI0_WREADY;
    //output        IP_MAXI0_WVALID;
   assign MAXI0_WDATA = IP_MAXI0_WDATA[63:0];
   assign MAXI0_WVALID = IP_MAXI0_WDATA[64];
   assign IP_MAXI0_WDATA_ready = MAXI0_WREADY;
   
    wire [7:0]  IP_MAXI0_WSTRB;
   assign MAXI0_WSTRB = IP_MAXI0_WSTRB;
    wire        IP_MAXI0_WLAST;
   assign MAXI0_WLAST = IP_MAXI0_WLAST;
   
    wire [2:0]   IP_MAXI0_BRESP;
    //input         IP_MAXI0_BVALID;
    //output        IP_MAXI0_BREADY;
   wire IP_MAXI0_BRESP_ready;
   assign IP_MAXI0_BRESP = {MAXI0_BVALID,MAXI0_BRESP};
   assign MAXI0_BREADY = IP_MAXI0_BRESP_ready;
   
    wire [3:0]  IP_MAXI0_AWLEN;
   assign MAXI0_AWLEN = IP_MAXI0_AWLEN;
    wire [1:0]  IP_MAXI0_AWSIZE;
   assign MAXI0_AWSIZE = IP_MAXI0_AWSIZE;
    wire [1:0]  IP_MAXI0_AWBURST;
   assign MAXI0_AWBURST = IP_MAXI0_AWBURST;

//IP_Top ipTop(.IP_MAXI0_ARADDR_ready(IP_MAXI0_ARREADY); .IP_MAXI0_ARADDR({IP_MAXI0_ARVALID,IP_MAXI0_ARADDR}), .IP_MAXI0_RDATA_ready(IP_MAXI0_RREADY), .IP_MAXI0_RDATA({IP_MAXI0_RVALID,IP_MAXI0_RDATA}), .IP_MAXI0_AWADDR_ready(IP_MAXI0_AWREADY), .IP_MAXI0_AWADDR({IP_MAXI0_AWVALID,IP_MAXI0_AWADDR}), .IP_MAXI0_WDATA_ready(IP_MAXI0_WREADY), .IP_MAXI0_WDATA({IP_MAXI0_WVALID,IP_MAXI0_WDATA}), .IP_MAXI0_BRESP_ready(IP_MAXI0_BREADY), .IP_MAXI0_BRESP({IP_MAXI0_BVALID,IP_MAXI0_BRESP}), .*);

   IP_Top ipTop(.*);
   
endmodule
