local types = require "types"
local J = require "common"

local AXI = {}

local vbase
vbase = J.memoize(function(ty,idx)
  if idx==0 then return 0
  else return vbase(ty,idx-1)+ty.list[idx]:verilogBits() end
end)

local function vrange(ty,idx,base)
  return "["..tostring(vbase(ty,idx+1)+base-1)..":"..tostring(vbase(ty,idx)+base).."]"
end

AXI.ReadAddressTuple = types.tuple{
  types.bits(32), -- ARADDR
  types.bits(8), -- ARLEN
  types.bits(3), -- ARSIZE
  types.bits(2), -- ARBURST
  types.bits(12), -- ARID
  types.bits(3), -- ARPROT
  types.bits(4), -- ARCACHE
  types.bool(), -- ARLOCK
  types.bits(4), -- ARREGION
  types.bits(6), -- ARUSER
  types.bits(4), -- ARQOS
}

AXI.ReadAddress = types.HandshakeVR(AXI.ReadAddressTuple)

AXI.ReadAddress64 = AXI.ReadAddress
AXI.ReadAddress32 = AXI.ReadAddress
AXI.ReadAddressIdx={araddr=0,arlen=1,arsize=2,arburst=3,arid=4,arprot=5,arcache=6,arlock=7,arregion=8,aruser=9,arqos=10}
AXI.ReadAddressVSelect = {arvalid="["..tostring(types.extractData(AXI.ReadAddress):verilogBits()).."]"}
for k,v in pairs(AXI.ReadAddressIdx) do AXI.ReadAddressVSelect[k] = vrange(types.extractData(AXI.ReadAddress),AXI.ReadAddressIdx[k],0) end

AXI.ReadDataTuple = J.memoize(function(bits)
  return types.tuple{
    types.bits(bits), -- RDATA
    types.bool(), -- RLAST
    types.bits(2), -- RRESP
    types.bits(12), -- RID
    types.bits(6) -- RUSER
  }
end)
  
AXI.ReadData = J.memoize(function(bits)
    assert(type(bits)=="number")
    return types.HandshakeVR(AXI.ReadDataTuple(bits))
end)

AXI.ReadData64 = AXI.ReadData(64)
AXI.ReadData32 = AXI.ReadData(32)

AXI.ReadDataIdx={rdata=0,rlast=1,rresp=2,rid=3,ruser=4}
AXI.ReadDataVSelect = J.memoize(function(bits)
    assert(type(bits)=="number")
    local tab = {rvalid="["..tostring(types.extractData(AXI.ReadData(bits)):verilogBits()).."]"}
    for k,v in pairs(AXI.ReadDataIdx) do tab[k] = vrange(types.extractData(AXI.ReadData(bits)),AXI.ReadDataIdx[k],0) end
    return tab
end)

-- 52 bits
AXI.WriteAddress = types.tuple{
  types.bits(32), -- AWADDR
  types.bits(8), -- AWLEN
  types.bits(2), -- AWBURST
  types.bits(3), -- AWSIZE
  types.bits(12), -- AWID
  types.bits(4), -- AWCACHE
  types.bits(3), -- AWPROT
  types.bits(4), --AWREGION
  types.bits(6), -- AWUSER
  types.bits(4), -- AWQOS
  types.bool() --AWLOCK
}
AXI.WriteAddressIdx={awaddr=0,awlen=1,awburst=2,awsize=3,awid=4,awcache=5,awprot=6,awregion=7,awuser=8,awqos=9,awlock=10}

AXI.WriteData = J.memoize(function(bits)
    assert(type(bits)=="number")
    return types.tuple{
      types.bits(bits), -- WDATA
      types.bits(J.sel(bits==64,8,4)), -- WSTRB
      types.bool(), -- WLAST
--      types.bits(12), -- WID
      types.bits(6), -- WUSER
    }
end)

AXI.WriteDataIdx = {wdata=0,wstrb=1,wlast=2,wuser=3} --wid=3,

AXI.WriteIssue = J.memoize(function(bits) return types.HandshakeVRTuple{AXI.WriteAddress,AXI.WriteData(bits)} end)
AXI.WriteIssue64 = AXI.WriteIssue(64)
AXI.WriteIssue32 = AXI.WriteIssue(32)

-- verilog bit select
AXI.WriteIssueVSelect = J.memoize(function(bits)
    local tab = {awvalid="["..tostring(AXI.WriteAddress:verilogBits()).."]",wvalid="["..tostring(AXI.WriteAddress:verilogBits()+1+AXI.WriteData(bits):verilogBits()).."]"}
    for k,v in pairs(AXI.WriteAddressIdx) do tab[k] = vrange(AXI.WriteAddress,AXI.WriteAddressIdx[k],0) end
    for k,v in pairs(AXI.WriteDataIdx) do tab[k] = vrange(AXI.WriteData(bits),AXI.WriteDataIdx[k],AXI.WriteAddress:verilogBits()+1) end
    return tab
end)

AXI.WriteResponseTuple = types.tuple{
  types.bits(2), -- BRESP
  types.bits(12), -- BID
  types.bits(6) -- BUSER
}

AXI.WriteResponse = J.memoize(function(bits)
    assert(type(bits)=="number")
    return types.HandshakeVR(AXI.WriteResponseTuple)
end)

AXI.WriteResponse64 = AXI.WriteResponse(64)
AXI.WriteResponse32 = AXI.WriteResponse(32)

AXI.WriteResponseIdx = {bresp=0,bid=1,buser=2}
AXI.WriteResponseVSelect = J.memoize(function(bits)
    local tab = {bvalid="["..tostring(types.extractData(AXI.WriteResponse(bits)):verilogBits()).."]"}
    for k,v in pairs(AXI.WriteResponseIdx) do tab[k] = vrange(types.extractData(AXI.WriteResponse(bits)),AXI.WriteResponseIdx[k],0) end
    return tab
end)

return AXI
