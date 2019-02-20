local types = require "types"

local AXI = {}

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

AXI.WriteAddress = types.tuple{
  types.bits(12), -- AWID
  types.bits(32), -- AWADDR
  types.bits(4), -- AWLEN
  types.bits(2), -- AWSIZE
  types.bits(2) -- AWBURST
}

AXI.WriteData = types.tuple{
  types.bits(12), -- WID
  types.bits(32), -- WDATA
  types.bits(4), -- WSTRB
  types.bool(), -- WLAST
}

AXI.WriteIssue = types.HandshakeTuple{AXI.WriteAddress,AXI.WriteData}

AXI.WriteResponse = types.Handshake(types.tuple{
  types.bits(12), -- BIT
  types.bits(3) -- BRESP
})

return AXI
