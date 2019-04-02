local R = require "rigel"
local types = require "types"
local AXI = require "axi"
local SDF = require "sdf"
local J = require "common"
local C = require "examplescommon"

local Pulpino = {}

-- readFn is the slave
Pulpino.AXIReadBusResize = J.memoize(function(readFn,masterSize,slaveSize,X)
  J.err( R.isFunction(readFn), "Pulpino.AXIReadBusResize: read function should be rigel function, but is: "..tostring(readFn) )
  J.err(type(masterSize)=="number","Pulpino.AXIReadBusResize: masterSize should be number, but is: "..tostring(masterSize))
  J.err(type(slaveSize)=="number","Pulpino.AXIReadBusResize: slaveSize should be number, but is: "..tostring(slaveSize))
  assert(masterSize~=slaveSize)

  assert( readFn.inputType==AXI.ReadAddress )
  J.err( readFn.outputType==AXI.ReadData(slaveSize), "Pulpino.AXIReadBusResize: readFn (slave) output type should be "..tostring(slaveSize)..", but is :"..tostring(readFn.outputType) )

  -- if slaveSize>masterSize, we can service requests at full rate
  local sdfIn, sdfOut = SDF{1,1}, SDF{1,1}
  if slaveSize<masterSize then
    sdfIn, sdfOut = SDF{slaveSize,masterSize}, SDF{slaveSize,masterSize}
  end
  
  local res = R.newFunction{ name="Pulpino_AXIReadBusResize_masterSize_"..tostring(masterSize).."_slaveSize_"..tostring(slaveSize), inputType=AXI.ReadAddress, outputType=AXI.ReadData(masterSize), sdfInput=sdfIn, sdfOutput=sdfOut, stateful=false }

  res.makeSystolic = function()
    local s = C.automaticSystolicStub(res)
    return s
  end
    
  return res
end)

Pulpino.AXIWriteBusResize = J.memoize(function(writeFn,masterSize,slaveSize,X)
  J.err( R.isFunction(writeFn), "Pulpino.AXIWriteBusResize: write function should be rigel function, but is: "..tostring(writeFn) )
  J.err(type(masterSize)=="number","Pulpino.AXIWriteBusResize: masterSize should be number, but is: "..tostring(masterSize))
  J.err(type(slaveSize)=="number","Pulpino.AXIWriteBusResize: slaveSize should be number, but is: "..tostring(slaveSize))
  assert(masterSize~=slaveSize)

  assert( writeFn.inputType==AXI.WriteIssue(slaveSize) )
  J.err( writeFn.outputType==AXI.WriteResponse(slaveSize), "Pulpino.AXIWriteBusResize: writeFn (slave) output type should be "..tostring(slaveSize)..", but is :"..tostring(writeFn.outputType) )

  -- if slaveSize>masterSize, we can service requests at full rate
  local sdfIn, sdfOut = SDF{1,1}, SDF{1,1}
  if slaveSize<masterSize then
    sdfIn, sdfOut = SDF{slaveSize,masterSize}, SDF{slaveSize,masterSize}
  end
  
  local res = R.newFunction{ name="Pulpino_AXIWriteBusResize_masterSize_"..tostring(masterSize).."_slaveSize_"..tostring(slaveSize), inputType=AXI.WriteIssue(masterSize), outputType=AXI.WriteResponse(masterSize), sdfInput=sdfIn, sdfOutput=sdfOut, stateful=false }

  res.makeSystolic = function()
    local s = C.automaticSystolicStub(res)
    return s
  end

  return res
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
