local AXI = require "axi"
local J = require "common"

-- this is just a script that autogenerates mpsoc_iptop_LL.sv using AXI.lua port defn

function assnExtToRigel(idx,src)
  local str = {}
  local iidx = J.invertTable(idx)
  for i=#iidx,0,-1 do table.insert(str,src..string.upper(iidx[i]) ) end
  return table.concat(str,",")
end

function assnRigelToExt(vtab,dest,src)
  local str = ""
  for k,v in pairs(vtab) do
    str = str.."assign "..dest..string.upper(k).." = "..src.."["..v..[[];
]]
  end
  return str
end

local READ_PORTS = ""

for i=1,2 do
  local PORT = "ZynqNOC_read"
  if i>1 then PORT=PORT..tostring(i-1) end
    
  READ_PORTS = READ_PORTS..[[wire         ]]..PORT..[[_ready_downstream;
   assign MAXI]]..(i-1)..[[_RREADY = ]]..PORT..[[_ready_downstream;
   wire   ]]..PORT..[[_ready;
   assign ]]..PORT..[[_ready = MAXI]]..(i-1)..[[_ARREADY;
   wire [55:0] ]]..PORT..[[_input; // read request
   ]]..assnRigelToExt(AXI.ReadAddressVSelect,"MAXI"..(i-1).."_",PORT.."_input")..[[
   wire [79:0] ]]..PORT..[[;    // read response
   assign ]]..PORT..[[ = {MAXI]]..(i-1)..[[_RVALID,]]..assnExtToRigel(AXI.ReadDataIdx,"MAXI"..(i-1).."_")..[[};
]]
end

print([[module VerilatorWrapper(
  input         IP_CLK,
  input         IP_ARESET_N,

    input [31:0]  SAXI0_ARADDR,
    input         SAXI0_ARVALID,
    input         SAXI0_ARLAST,
    input  [1:0]  SAXI0_ARBURST,
    input  [3:0]  SAXI0_ARLEN,
    input  [2:0]  SAXI0_ARPROT,
    input   [1:0] SAXI0_ARSIZE,
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

   wire []]..tostring(AXI.WriteIssue(64):verilogBits()-1)..[[:0] ZynqNOC_write_input; // write issue
   ]]..assnRigelToExt(AXI.WriteIssueVSelect(64),"MAXI0_","ZynqNOC_write_input")..[[
   wire [14:0]  ZynqNOC_write; // write response
   assign ZynqNOC_write = {MAXI0_BVALID,]]..assnExtToRigel(AXI.WriteResponseIdx,"MAXI0_")..[[};
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
   assign ZynqNOC_writeSource[]]..tostring(AXI.WriteAddress:verilogBits())..[[:0] = {SAXI0_AWVALID,]]..assnExtToRigel(AXI.WriteAddressIdx,"SAXI0_")..[[};
   assign ZynqNOC_writeSource[]]..tostring(AXI.WriteAddress:verilogBits()+AXI.WriteData(32):verilogBits()+1)..[[:]]..tostring(AXI.WriteAddress:verilogBits()+1)..[[] = {SAXI0_WVALID,]]..assnExtToRigel(AXI.WriteDataIdx,"SAXI0_")..[[};
   wire []]..tostring(AXI.WriteResponse(32):verilogBits()-1)..[[:0] ZynqNOC_writeSink_input; // return write result from slave
   ]]..assnRigelToExt(AXI.WriteResponseVSelect(32),"SAXI0_","ZynqNOC_writeSink_input")..[[
   wire []]..tostring(AXI.ReadAddress:verilogBits()-1)..[[:0] ZynqNOC_readSource;  // issue read to slave
   assign ZynqNOC_readSource = {SAXI0_ARVALID,]]..assnExtToRigel(AXI.ReadAddressIdx,"SAXI0_")..[[};
   wire [47:0] ZynqNOC_readSink_input;  // slave read response
   ]]..assnRigelToExt(AXI.ReadDataVSelect(32),"SAXI0_","ZynqNOC_readSink_input")..[[

   ]]..READ_PORTS..[[

   Top top(.CLK(IP_CLK), .reset(~IP_ARESET_N), .*);

endmodule]])
