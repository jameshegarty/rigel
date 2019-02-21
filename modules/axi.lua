local types = require "types"
local J = require "common"

local AXI = {}

local vbase
vbase = J.memoize(function(ty,idx)
  if idx==0 then return 0
  else return vbase(ty,idx-1)+ty.list[idx]:verilogBits() end
end)

local function vrange(ty,idx,base)
  return tostring(vbase(ty,idx+1)+base-1)..":"..tostring(vbase(ty,idx)+base)
end

AXI.ReadAddress = types.Handshake(types.tuple{
  types.bits(32), -- ARADDR
  types.bits(4), -- ARLEN
  types.bits(2), -- ARSIZE
  types.bits(2), -- ARBURST
  types.bits(12), -- ARID
  types.bits(3) -- ARPROT
})

AXI.ReadData = types.Handshake(types.tuple{
  types.bits(64), -- RDATA
  types.bool(), -- RLAST
  types.bits(2), -- RRESP
  types.bits(12), -- RID
})

-- 52 bits
AXI.WriteAddress = types.tuple{
  types.bits(32), -- AWADDR
  types.bits(4), -- AWLEN
  types.bits(2), -- AWBURST
  types.bits(2), -- AWSIZE
  types.bits(12) -- AWID
}
AXI.WriteAddressIdx={awaddr=0,awlen=1,awburst=2,awsize=3,awid=4}

AXI.WriteData = types.tuple{
  types.bits(64), -- WDATA
  types.bits(8), -- WSTRB
  types.bool(), -- WLAST
  types.bits(12) -- WID
}
AXI.WriteDataIdx = {wdata=0,wstrb=1,wlast=2,wid=3}

AXI.WriteIssue = types.HandshakeTuple{AXI.WriteAddress,AXI.WriteData}

-- verilog bit select
AXI.WriteIssueVSelect = {awvalid=tostring(AXI.WriteAddress:verilogBits()),wvalid=tostring(AXI.WriteAddress:verilogBits()+1+AXI.WriteData:verilogBits())}
for k,v in pairs(AXI.WriteAddressIdx) do AXI.WriteIssueVSelect[k] = vrange(AXI.WriteAddress,AXI.WriteAddressIdx[k],0) end
for k,v in pairs(AXI.WriteDataIdx) do AXI.WriteIssueVSelect[k] = vrange(AXI.WriteData,AXI.WriteDataIdx[k],AXI.WriteAddress:verilogBits()+1) end

AXI.WriteResponse = types.Handshake(types.tuple{
--  types.bits(12), -- BIT
  types.bits(2) -- BRESP
})
AXI.WriteResponseIdx = {bresp=0}
AXI.WriteResponseVSelect = {bvalid=tostring(types.extractData(AXI.WriteResponse):verilogBits())}
for k,v in pairs(AXI.WriteResponseIdx) do AXI.WriteResponseVSelect[k] = vrange(types.extractData(AXI.WriteResponse),AXI.WriteResponseIdx[k],0) end

return AXI
