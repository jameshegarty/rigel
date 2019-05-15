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
    str = str.."assign "..dest..string.upper(k).." = "..src..v..[[;
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
   wire []]..(AXI.ReadAddress:verilogBits()-1)..[[:0] ]]..PORT..[[_input; // read request
   ]]..assnRigelToExt(AXI.ReadAddressVSelect,"MAXI"..(i-1).."_",PORT.."_input")..[[
   wire []]..(AXI.ReadData64:verilogBits()-1)..[[:0] ]]..PORT..[[_output;    // read response
   assign ]]..PORT..[[_output = {MAXI]]..(i-1)..[[_RVALID,]]..assnExtToRigel(AXI.ReadDataIdx,"MAXI"..(i-1).."_")..[[};
]]
end

function makePort(prefix,input,bits)
  local vstr = {}
  for k,idx in pairs(AXI.ReadAddressIdx) do
    table.insert(vstr, J.sel(input,"input","output").." ["..(AXI.ReadAddressTuple.list[idx+1]:verilogBits()-1)..":0] "..prefix..string.upper(k))
  end

  table.insert(vstr,J.sel(input,"input","output").." "..prefix.."ARVALID")
  table.insert(vstr,J.sel(input,"output","input").." "..prefix.."ARREADY")
  
  for k,idx in pairs(AXI.ReadDataIdx) do
    table.insert(vstr, J.sel(input,"output","input").." ["..(AXI.ReadDataTuple(bits).list[idx+1]:verilogBits()-1)..":0] "..prefix..string.upper(k))
  end

  table.insert(vstr,J.sel(input,"output","input").." "..prefix.."RVALID")
  table.insert(vstr,J.sel(input,"input","output").." "..prefix.."RREADY")
  
  for k,idx in pairs(AXI.WriteAddressIdx) do
    table.insert(vstr, J.sel(input,"input","output").." ["..(AXI.WriteAddress.list[idx+1]:verilogBits()-1)..":0] "..prefix..string.upper(k))
  end

  table.insert(vstr,J.sel(input,"output","input").." "..prefix.."AWREADY")
  table.insert(vstr,J.sel(input,"input","output").." "..prefix.."AWVALID")
  
  for k,idx in pairs(AXI.WriteDataIdx) do
    table.insert(vstr, J.sel(input,"input","output").." ["..(AXI.WriteData(bits).list[idx+1]:verilogBits()-1)..":0] "..prefix..string.upper(k))
  end

  table.insert(vstr,J.sel(input,"output","input").." "..prefix.."WREADY")
  table.insert(vstr,J.sel(input,"input","output").." "..prefix.."WVALID")
  
  for k,idx in pairs(AXI.WriteResponseIdx) do
    table.insert(vstr, J.sel(input,"output","input").." ["..(AXI.WriteResponseTuple.list[idx+1]:verilogBits()-1)..":0] "..prefix..string.upper(k))
  end

  table.insert(vstr,J.sel(input,"input","output").." "..prefix.."BREADY")
  table.insert(vstr,J.sel(input,"output","input").." "..prefix.."BVALID")
  
  return table.concat(vstr,",\n")
end

print([[module VerilatorWrapper(
  input         IP_CLK,
  input         IP_ARESET_N,

]]..makePort("SAXI0_",true,32)..[[,
]]..makePort("MAXI0_",false,64)..[[,
]]..makePort("MAXI1_",false,64)..[[
);

   wire []]..tostring(AXI.WriteIssue(64):verilogBits()-1)..[[:0] ZynqNOC_write_input; // write issue
   ]]..assnRigelToExt(AXI.WriteIssueVSelect(64),"MAXI0_","ZynqNOC_write_input")..[[
   wire []]..tostring(AXI.WriteResponse(64):verilogBits()-1)..[[:0]  ZynqNOC_write_output; // write response
   assign ZynqNOC_write_output = {MAXI0_BVALID,]]..assnExtToRigel(AXI.WriteResponseIdx,"MAXI0_")..[[};
   wire ZynqNOC_write_ready_downstream;  
   assign MAXI0_BREADY = ZynqNOC_write_ready_downstream;
   wire [1:0] ZynqNOC_write_ready;  
   assign ZynqNOC_write_ready = {MAXI0_WREADY,MAXI0_AWREADY};  

   ////////////////
   wire         regs_read_ready_downstream;
   assign regs_read_ready_downstream = SAXI0_RREADY;
   wire         regs_read_ready;
   assign SAXI0_ARREADY = regs_read_ready;
   wire []]..tostring(AXI.ReadAddress:verilogBits()-1)..[[:0] regs_read_input;  // issue read to slave
   assign regs_read_input = {SAXI0_ARVALID,]]..assnExtToRigel(AXI.ReadAddressIdx,"SAXI0_")..[[};
   wire []]..tostring(AXI.ReadDataTuple(32):verilogBits())..[[:0] regs_read_output;  // slave read response
   ]]..assnRigelToExt(AXI.ReadDataVSelect(32),"SAXI0_","regs_read_output")..[[

   wire         regs_write_ready_downstream;
   assign regs_write_ready_downstream = SAXI0_BREADY;
   wire [1:0] regs_write_ready; 
   assign SAXI0_AWREADY = regs_write_ready[0];
   assign SAXI0_WREADY = regs_write_ready[1];
   wire []]..tostring(AXI.WriteIssue(32):verilogBits()-1)..[[:0] regs_write_input;  // issue write to slave
   assign regs_write_input[]]..tostring(AXI.WriteAddress:verilogBits())..[[:0] = {SAXI0_AWVALID,]]..assnExtToRigel(AXI.WriteAddressIdx,"SAXI0_")..[[};
   assign regs_write_input[]]..tostring(AXI.WriteAddress:verilogBits()+AXI.WriteData(32):verilogBits()+1)..[[:]]..tostring(AXI.WriteAddress:verilogBits()+1)..[[] = {SAXI0_WVALID,]]..assnExtToRigel(AXI.WriteDataIdx,"SAXI0_")..[[};
   wire []]..tostring(AXI.WriteResponse(32):verilogBits()-1)..[[:0] regs_write_output; // return write result from slave
   ]]..assnRigelToExt(AXI.WriteResponseVSelect(32),"SAXI0_","regs_write_output")..[[
   /////////////////////

   ]]..READ_PORTS..[[

   Top top(.CLK(IP_CLK), .reset(~IP_ARESET_N), .*);

endmodule]])
