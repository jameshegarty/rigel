local types = require "types"
local AXI = require "axi"

local AXIT = {}

local data = macro(function(i) return `i._0 end)
local valid = macro(function(i) return `i._1 end)

-- do this using functions instead of macros so that we get a little bit of type correctness...

local function ReadAddressLookup(idx) return macro(function(tab) return `&data(tab).["_"..AXI.ReadAddressIdx[idx]] end) end

terra AXIT.ARVALID(inp:&types.lower(AXI.ReadAddress):toTerraType()) return &valid(inp) end
terra AXIT.ARADDR(inp:&types.lower(AXI.ReadAddress):toTerraType()) return [ReadAddressLookup("araddr")](inp) end
terra AXIT.ARLEN(inp:&types.lower(AXI.ReadAddress):toTerraType()) return [ReadAddressLookup("arlen")](inp) end
terra AXIT.ARSIZE(inp:&types.lower(AXI.ReadAddress):toTerraType()) return [ReadAddressLookup("arsize")](inp) end
terra AXIT.ARBURST(inp:&types.lower(AXI.ReadAddress):toTerraType()) return [ReadAddressLookup("arburst")](inp) end
terra AXIT.ARID(inp:&types.lower(AXI.ReadAddress):toTerraType()) return [ReadAddressLookup("arid")](inp) end
terra AXIT.ARPROT(inp:&types.lower(AXI.ReadAddress):toTerraType()) return [ReadAddressLookup("arprot")](inp) end

AXIT.ARVALID64 = AXIT.ARVALID
AXIT.ARADDR64 = AXIT.ARADDR
AXIT.ARLEN64 = AXIT.ARLEN
AXIT.ARSIZE64 = AXIT.ARSIZE
AXIT.ARBURST64 = AXIT.ARBURST
AXIT.ARID64 = AXIT.ARID
AXIT.ARPROT64 = AXIT.ARPROT

AXIT.ARVALID32 = AXIT.ARVALID
AXIT.ARADDR32 = AXIT.ARADDR
AXIT.ARLEN32 = AXIT.ARLEN
AXIT.ARSIZE32 = AXIT.ARSIZE
AXIT.ARBURST32 = AXIT.ARBURST
AXIT.ARID32 = AXIT.ARID
AXIT.ARPROT32 = AXIT.ARPROT

local function ReadDataLookup(idx) return macro(function(tab) return `&data(tab).["_"..AXI.ReadDataIdx[idx]] end) end

function AXIT.RVALID(bts) return terra(inp:&types.lower(AXI.ReadData(bts)):toTerraType()) return &valid(inp) end end
function AXIT.RDATA(bts) return terra(inp:&types.lower(AXI.ReadData(bts)):toTerraType()) return [ReadDataLookup("rdata")](inp) end end
function AXIT.RLAST(bts) return terra(inp:&types.lower(AXI.ReadData(bts)):toTerraType()) return [ReadDataLookup("rlast")](inp) end end
function AXIT.RRESP(bts) return terra(inp:&types.lower(AXI.ReadData(bts)):toTerraType()) return [ReadDataLookup("rresp")](inp) end end
function AXIT.RID(bts) return terra(inp:&types.lower(AXI.ReadData(bts)):toTerraType()) return [ReadDataLookup("rid")](inp) end end
AXIT.RVALID64 = AXIT.RVALID(64)
AXIT.RDATA64 = AXIT.RDATA(64)
AXIT.RLAST64 = AXIT.RLAST(64)
AXIT.RRESP64 = AXIT.RRESP(64)
AXIT.RID64 = AXIT.RID(64)

AXIT.RVALID32 = AXIT.RVALID(32)
AXIT.RDATA32 = AXIT.RDATA(32)
AXIT.RLAST32 = AXIT.RLAST(32)
AXIT.RRESP32 = AXIT.RRESP(32)
AXIT.RID32 = AXIT.RID(32)

local function WriteAddressLookup(idx) return macro(function(tab) return `&data(tab._0).["_"..AXI.WriteAddressIdx[idx]] end) end

function AXIT.AWVALID(bts) return terra(inp:&types.lower(AXI.WriteIssue(bts)):toTerraType()) return &valid(inp._0) end end
function AXIT.AWADDR(bts) return terra(inp:&types.lower(AXI.WriteIssue(bts)):toTerraType()) return [WriteAddressLookup("awaddr")](inp) end end
function AXIT.AWLEN(bts) return terra(inp:&types.lower(AXI.WriteIssue(bts)):toTerraType()) return [WriteAddressLookup("awlen")](inp) end end
function AXIT.AWSIZE(bts) return terra(inp:&types.lower(AXI.WriteIssue(bts)):toTerraType()) return [WriteAddressLookup("awsize")](inp) end end
function AXIT.AWBURST(bts) return terra(inp:&types.lower(AXI.WriteIssue(bts)):toTerraType()) return [WriteAddressLookup("awburst")](inp) end end
function AXIT.AWID(bts) return terra(inp:&types.lower(AXI.WriteIssue(bts)):toTerraType()) return [WriteAddressLookup("awid")](inp) end end
AXIT.AWVALID32 = AXIT.AWVALID(32)
AXIT.AWADDR32 = AXIT.AWADDR(32)
AXIT.AWLEN32 = AXIT.AWLEN(32)
AXIT.AWSIZE32 = AXIT.AWSIZE(32)
AXIT.AWBURST32 = AXIT.AWBURST(32)
AXIT.AWID32 = AXIT.AWID(32)

AXIT.AWVALID64 = AXIT.AWVALID(64)
AXIT.AWADDR64 = AXIT.AWADDR(64)
AXIT.AWLEN64 = AXIT.AWLEN(64)
AXIT.AWSIZE64 = AXIT.AWSIZE(64)
AXIT.AWBURST64 = AXIT.AWBURST(64)
AXIT.AWID64 = AXIT.AWID(64)

local function WriteDataLookup(idx) return macro(function(tab)
      if AXI.WriteDataIdx[idx]==nil then print("MISSING?",idx) end
      return `&data(tab._1).["_"..AXI.WriteDataIdx[idx]] end) end
function AXIT.WVALID(bts) return terra(inp:&types.lower(AXI.WriteIssue(bts)):toTerraType()) return &valid(inp._1) end end
function AXIT.WDATA(bts) return terra(inp:&types.lower(AXI.WriteIssue(bts)):toTerraType()) return [WriteDataLookup("wdata")](inp) end end
function AXIT.WSTRB(bts) return terra(inp:&types.lower(AXI.WriteIssue(bts)):toTerraType()) return [WriteDataLookup("wstrb")](inp) end end
function AXIT.WLAST(bts) return terra(inp:&types.lower(AXI.WriteIssue(bts)):toTerraType()) return [WriteDataLookup("wlast")](inp) end end
--function AXIT.WID(bts) return terra(inp:&types.lower(AXI.WriteIssue(bts)):toTerraType()) return [WriteDataLookup("wid")](inp) end end
AXIT.WVALID32 = AXIT.WVALID(32)
AXIT.WVALID64 = AXIT.WVALID(64)
AXIT.WDATA32 = AXIT.WDATA(32)
AXIT.WDATA64 = AXIT.WDATA(64)
AXIT.WSTRB64 = AXIT.WSTRB(64)
AXIT.WSTRB32 = AXIT.WSTRB(32)
AXIT.WLAST64 = AXIT.WLAST(64)
AXIT.WLAST32 = AXIT.WLAST(32)
--AXIT.WID64 = AXIT.WID(64)
--AXIT.WID32 = AXIT.WID(32)

local function WriteResponseLookup(idx)
  return macro(function(tab) return `&data(tab).["_"..AXI.WriteResponseIdx[idx]] end)
end


function AXIT.BRESP(bts) return terra(inp:&types.lower(AXI.WriteResponse(bts)):toTerraType()) return [WriteResponseLookup("bresp")](inp) end end
function AXIT.BID(bts) return terra(inp:&types.lower(AXI.WriteResponse(bts)):toTerraType()) return [WriteResponseLookup("bid")](inp) end end
function AXIT.BVALID(bts) return terra(inp:&types.lower(AXI.WriteResponse(bts)):toTerraType()) return &valid(inp) end end
AXIT.BRESP32 = AXIT.BRESP(32)
AXIT.BVALID32 = AXIT.BVALID(32)
AXIT.BID32 = AXIT.BID(32)

AXIT.BRESP64 = AXIT.BRESP(64)
AXIT.BVALID64 = AXIT.BVALID(64)
AXIT.BID64 = AXIT.BID(64)

return AXIT
