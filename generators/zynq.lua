local R = require "rigel"
local RM = require "generators.modules"
local AXI = require "generators.axi"
local SDF = require "sdf"
local J = require "common"
local Uniform = require "uniform"
local types = require "types"
local C = require "generators.examplescommon"

local Zynq = {}

Zynq.SimpleNOC = J.memoize(function(readPorts,writePorts,slavePorts,X)
  assert(X==nil)

  if readPorts==nil then readPorts=1 end
  if writePorts==nil then writePorts=1 end

  local SimpleNOCFns = {}
--  SimpleNOCFns.readSource = R.newFunction{name="ReadSource",inputType=types.null(),outputType=AXI.ReadAddress,sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false, sdfExact=true}
--  SimpleNOCFns.readSink = R.newFunction{name="ReadSink",inputType=AXI.ReadData(32),outputType=types.null(),sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false}
  
--  SimpleNOCFns.writeSource = R.newFunction{name="WriteSource",inputType=types.null(),outputType=AXI.WriteIssue(32),sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false, sdfExact=true}
--  SimpleNOCFns.writeSink = R.newFunction{name="WriteSink",inputType=AXI.WriteResponse(32),outputType=types.null(),sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false}

  for i=1,readPorts do
    SimpleNOCFns["read"..J.sel(i==1,"",tostring(i-1))] = R.newFunction{name="Read",inputType=AXI.ReadAddress,outputType=AXI.ReadData(64),sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false}
  end
  
  SimpleNOCFns.write = R.newFunction{name="Write",inputType=AXI.WriteIssue(64), outputType=AXI.WriteResponse(64), sdfInput=SDF{{1,1},{1,1}},sdfOutput=SDF{1,1}, stateful=false}

  local makeTerra
  if terralib~=nil then
    makeTerra = require "generators.zynqTerra"
  end
  

  local instanceList = {}
  if slavePorts~=nil then
    for k,v in pairs(slavePorts) do
      J.err( R.isFunction(v[1]), "Zynq.SimpleNOC: slave read should be rigel function, but is: "..tostring(v[1]))
      J.err( v[1].inputType==AXI.ReadAddress32 and v[1].outputType==AXI.ReadData32, "Zynq.SimpleNOC: slave read should have type AXI.ReadAddress32->AXI.ReadData32")
      
      J.err( R.isFunction(v[2]), "Zynq.SimpleNOC: slave write should be rigel function, but is: "..tostring(v[2]))
      print("AXIWRITEISSUE32",AXI.WriteIssue32)
      print("AXIWRITERESP32",AXI.WriteResponse32)
      J.err( v[2].inputType==AXI.WriteIssue32 and v[2].outputType==AXI.WriteResponse32, "Zynq.SimpleNOC: write should have type AXI.WriteIssue32->AXI.WriteResponse32, but is: "..tostring(v[2].inputType).."->"..tostring(v[2].outputType))
      
      table.insert(instanceList,v[1]:instantiate("readSlave"))
      table.insert(instanceList,v[2]:instantiate("writeSlave"))
    end
  end

  local NOC = RM.moduleLambda( "Zynq_NOC", SimpleNOCFns, instanceList )
  NOC.makeSystolic = function() return C.automaticSystolicStub(NOC) end
  NOC.makeTerra = function() return makeTerra(readPorts,writePorts) end
  NOC.readPorts = readPorts
  NOC.writePorts = writePorts

  return NOC
end)

return Zynq
