local R = require "rigel"
local AXI = require "axi"
local SDF = require "sdf"
local J = require "common"
local Uniform = require "uniform"
local types = require "types"
local C = require "examplescommon"

local Zynq = {}

--[=[
Zynq.NOC = R.newModuleGenerator("Zynq","NOC",{},{},
{readPorts={},writePorts={},address=0x30008000,responderAddress=0xA0000008},
function( moduleGenInst, fnName, args)
  if fnName=="read" then
    print("ZYNQ READ")
    for k,v in pairs(args) do print("ZR ",k,v) end
    J.err( args.type==AXI.ReadAddress, "Zynq.NOC read: expected AXI.ReadAddress as input type, but was: "..tostring(args.type) )
    J.err( SDF.isSDF(args.rate), "Zynq.NOC read: missing SDF rate?" )
    J.err( type(args.number)=="number","Zynq.NOC read: expected a number, which is the size of region to read from" )
    local res = { name="Zynq_NOC_Read_Port_"..tostring(#moduleGenInst.readPorts), inputType=args.type, outputType=AXI.ReadData, stateful=false, sdfInput=args.rate, sdfOutput=args.rate }
    res.meta={port=#moduleGenInst.readPorts,address = moduleGenInst.address}
    res.localMetadataKeys = {["port"]=1,["address"]=1}
    print("MGA",moduleGenInst,moduleGenInst.address)
    moduleGenInst.address = moduleGenInst.address + Uniform(args.number):maximum()
    res = R.newFunction(res)
    table.insert(moduleGenInst.readPorts,res)
    return res
  elseif fnName=="write" then
    J.err( args.type==AXI.WriteIssue, "Zynq.NOC read: expected AXI.WriteIssue as input type, but was: "..tostring(args.type) )
    J.err( SDF.isSDF(args.rate), "Zynq.NOC write: missing SDF rate?" )
    J.err( type(args.number)=="number","Zynq.NOC read: expected a number, which is the size of region to read from" )

    local res = { name="Zynq_NOC_Write_Port_"..tostring(#moduleGenInst.writePorts), inputType=args.type, outputType=AXI.WriteResponse, stateful=false, sdfInput=args.rate, sdfOutput=args.rate }
    res.meta={port=#moduleGenInst.writePorts,address = moduleGenInst.address}
    res.localMetadataKeys = {["port"]=1,["address"]=1}
    print("MGA",moduleGenInst,moduleGenInst.address)
    moduleGenInst.address = moduleGenInst.address + Uniform(args.number):maximum()
    res = R.newFunction(res)
    table.insert(moduleGenInst.writePorts,res)
    return res

  else
    J.err( false, "Zynq.NOC: unsupported fn call: "..fnName)
  end
end,
function( moduleGenInst )

end)
]=]

-- for regs: issueRead, readResponse, issueWrite, writeResponse
-- for IP DMAs: read, write


Zynq.SimpleNOC = J.memoize(function(readPorts,writePorts)
  if readPorts==nil then readPorts=1 end
  if writePorts==nil then writePorts=1 end

  local SimpleNOCFns = {}
  SimpleNOCFns.readSource = R.newFunction{name="ReadSource",inputType=types.null(),outputType=AXI.ReadAddress,sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false, sdfExact=true}
  SimpleNOCFns.readSink = R.newFunction{name="ReadSink",inputType=AXI.ReadData(32),outputType=types.null(),sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false}
  
  SimpleNOCFns.writeSource = R.newFunction{name="WriteSource",inputType=types.null(),outputType=AXI.WriteIssue(32),sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false, sdfExact=true}
  SimpleNOCFns.writeSink = R.newFunction{name="WriteSink",inputType=AXI.WriteResponse(32),outputType=types.null(),sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false}

  for i=1,readPorts do
    SimpleNOCFns["read"..J.sel(i==1,"",tostring(i-1))] = R.newFunction{name="Read",inputType=AXI.ReadAddress,outputType=AXI.ReadData(64),sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false}
  end
  
  SimpleNOCFns.write = R.newFunction{name="Write",inputType=AXI.WriteIssue(64), outputType=AXI.WriteResponse(64), sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false}

  local makeTerra
  if terralib~=nil then
    makeTerra = require "zynqTerra"
  end
  
  local NOC = R.newModule("Zynq_NOC",SimpleNOCFns,false,nil,function() return makeTerra(readPorts,writePorts) end)
  NOC.makeSystolic = function() return C.automaticSystolicStub(NOC) end
  NOC.readPorts = readPorts
  NOC.writePorts = writePorts
  
  return NOC
end)

return Zynq
