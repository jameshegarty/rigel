local R = require "rigel"
local types = require "types"
local AXI = require "axi"
local SDF = require "sdf"
local J = require "common"

local Pulpino = {}

Pulpino.AXIReadBusResize = J.memoize(function(from,to,X)
  local res = RM.lambda("Pulpino_AXIReadBusResize_from_"..tostring(from).."_to_"..tostring(to),
end)
  
-- NMaster and NSlave are the number of masters/slaves we want to connect
--   (not the # of ports on the interface)
Pulpino.AXIInterconnect = J.memoize(function(NMaster,NSlave,X)
    local SimpleNOCFns = {}

  for i=0,NSlave-1 do
    SimpleNOCFns["readSource"..tostring(i)] = R.newFunction{name="ReadSource"..tostring(i),inputType=types.null(),outputType=AXI.ReadAddress,sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false, sdfExact=true}
    SimpleNOCFns["readSink"..tostring(i)] = R.newFunction{name="ReadSink"..tostring(i),inputType=AXI.ReadData(64),outputType=types.null(),sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false}
  
    SimpleNOCFns["writeSource"..tostring(i)] = R.newFunction{name="WriteSource"..tostring(i),inputType=types.null(),outputType=AXI.WriteIssue(64),sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false, sdfExact=true}
    SimpleNOCFns["writeSink"..tostring(i)] = R.newFunction{name="WriteSink"..tostring(i),inputType=AXI.WriteResponse(64),outputType=types.null(),sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false}
  end

  for i=0,NMaster-1 do
    SimpleNOCFns["read"..tostring(i)] = R.newFunction{name="Read"..tostring(i),inputType=AXI.ReadAddress,outputType=AXI.ReadData(64),sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false}

    SimpleNOCFns["write"..tostring(i)] = R.newFunction{name="Write"..tostring(i),inputType=AXI.WriteIssue(64), outputType=AXI.WriteResponse(64), sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false}
  end

  local NOC = R.newModule("Pulpino_AXIInterconnect",SimpleNOCFns,false)

  NOC.makeSystolic = function()
    local s = C.automaticSystolicStub(NOC)
    return s
  end

  return NOC
end)

return Pulpino
