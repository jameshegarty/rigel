local R = require "rigel"
local RM = require "modules"
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

  local readInst = readFn:instantiate("readFn")
  
  local function vstr(rmod)
    return rmod:vHeader()
  end
  
  local res = RM.liftVerilogTab{ name="Pulpino_AXIReadBusResize_masterSize_"..tostring(masterSize).."_slaveSize_"..tostring(slaveSize), inputType=AXI.ReadAddress, outputType=AXI.ReadData(masterSize), sdfInput=sdfIn, sdfOutput=sdfOut, stateful=false, vstr=vstr, instanceMap={[readInst]=1} }

--  res.makeSystolic = function()
--    local s = C.automaticSystolicStub(res)
--    return s
--  end
    
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

  local writeInst = writeFn:instantiate("writeFn")
  
  local function vstr(rmod)
    return rmod:vHeader()
  end

  local res = RM.liftVerilogTab{ name="Pulpino_AXIWriteBusResize_masterSize_"..tostring(masterSize).."_slaveSize_"..tostring(slaveSize), inputType=AXI.WriteIssue(masterSize), outputType=AXI.WriteResponse(masterSize), sdfInput=sdfIn, sdfOutput=sdfOut, stateful=false, vstr=vstr, instanceMap={[writeInst]=1} }

--  res.makeSystolic = function()
--    local s = C.automaticSystolicStub(res)
--    return s
--  end

  return res
end)

-- NMaster and NSlave are the number of masters/slaves we want to connect
--   (not the # of ports on the interface)
Pulpino.AXIInterconnect = J.memoize(function( NMaster, NSlave, slavePorts, X )
  assert(X==nil)
    
  local SimpleNOCFns = {}

--[=[  for i=0,NSlave-1 do
    SimpleNOCFns["readSource"..tostring(i)] = R.newFunction{name="ReadSource"..tostring(i),inputType=types.null(),outputType=AXI.ReadAddress,sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false, sdfExact=true}
    SimpleNOCFns["readSink"..tostring(i)] = R.newFunction{name="ReadSink"..tostring(i),inputType=AXI.ReadData(64),outputType=types.null(),sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false}
  
    SimpleNOCFns["writeSource"..tostring(i)] = R.newFunction{name="WriteSource"..tostring(i),inputType=types.null(),outputType=AXI.WriteIssue(64),sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false, sdfExact=true}
    SimpleNOCFns["writeSink"..tostring(i)] = R.newFunction{name="WriteSink"..tostring(i),inputType=AXI.WriteResponse(64),outputType=types.null(),sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false}
  end]=]

  for i=0,NMaster-1 do
    SimpleNOCFns["read"..J.sel(i==0,"",tostring(i))] = R.newFunction{name="Read"..J.sel(i==0,"",tostring(i)),inputType=AXI.ReadAddress,outputType=AXI.ReadData(64),sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false}

    SimpleNOCFns["write"..J.sel(i==0,"",tostring(i))] = R.newFunction{name="Write"..J.sel(i==0,"",tostring(i)),inputType=AXI.WriteIssue(64), outputType=AXI.WriteResponse(64), sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false}
  end

  local instanceList = {}
  if slavePorts~=nil then
    for k,v in pairs(slavePorts) do
      J.err( R.isFunction(v[1]), "Pulpino_AXIInterconnect: slave read should be rigel function, but is: "..tostring(v[1]))
      J.err( v[1].inputType==AXI.ReadAddress64 and v[1].outputType==AXI.ReadData64, "Pulpino_AXIInterconnect: slave read should have type AXI.ReadAddress32->AXI.ReadData32, but is: "..tostring(v[1].inputType).."->"..tostring(v[1].outputType))
      
      J.err( R.isFunction(v[2]), "Pulpino_AXIInterconnect: slave write should be rigel function, but is: "..tostring(v[2]))
      J.err( v[2].inputType==AXI.WriteIssue64 and v[2].outputType==AXI.WriteResponse64, "Pulpino_AXIInterconnect: write should have type AXI.WriteIssue32->AXI.WriteResponse32, but is: "..tostring(v[2].inputType).."->"..tostring(v[2].outputType))
      
      table.insert( instanceList, v[1]:instantiate("slaveRead"..k) )
      table.insert( instanceList, v[2]:instantiate("slaveWrite"..k) )
      print(v[1],v[2])
    end
  end

  local axi_node = C.VerilogFile("modules/axi_node/src/axi_node.sv",{})
  print(axi_node)
  
  table.insert(instanceList, axi_node:instantiate("axi_node_inst"))
  
  local NOC = RM.moduleLambda("Pulpino_AXIInterconnect",SimpleNOCFns,instanceList)

  NOC.makeSystolic = function()
    local s = C.automaticSystolicStub(NOC)

    local vstr = {NOC:vHeader()}

    table.insert(vstr,[=[
  axi_node #(.N_MASTER_PORT(]=]..NMaster..[=[),.N_SLAVE_PORT(]=]..#slavePorts..[=[)) axi_node_inst();
endmodule

]=])

    
    s:verilog(table.concat(vstr,"\n"))
    return s
  end

  return NOC
end)

return Pulpino
