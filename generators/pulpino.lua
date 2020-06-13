local R = require "rigel"
local RM = require "generators.modules"
local types = require "types"
local AXI = require "generators.axi"
local SDF = require "sdf"
local J = require "common"
local C = require "generators.examplescommon"

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
    SimpleNOCFns["read"..J.sel(i==0,"",tostring(i))] = R.newFunction{name="Read"..J.sel(i==0,"",tostring(i)),inputType=AXI.ReadAddress,outputType=AXI.ReadData(64),sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false, delay=2}

    SimpleNOCFns["write"..J.sel(i==0,"",tostring(i))] = R.newFunction{name="Write"..J.sel(i==0,"",tostring(i)),inputType=AXI.WriteIssue(64), outputType=AXI.WriteResponse(64), sdfInput=SDF{{1,1},{1,1}},sdfOutput=SDF{1,1}, stateful=false, delay=2}
  end

  local instanceList = {}
  local slaveReadInst = {}
  local slaveWriteInst = {}
  if slavePorts~=nil then
    for k,v in ipairs(slavePorts) do
      J.err( R.isFunction(v[1]), "Pulpino_AXIInterconnect: slave read should be rigel function, but is: ",v[1])
      J.err( v[1].inputType==AXI.ReadAddress64 and v[1].outputType==AXI.ReadData64, "Pulpino_AXIInterconnect: slave read should have type AXI.ReadAddress32->AXI.ReadData32, but is: "..tostring(v[1].inputType).."->"..tostring(v[1].outputType))
      
      J.err( R.isFunction(v[2]), "Pulpino_AXIInterconnect: slave write should be rigel function, but is: ",v[2])
      J.err( v[2].inputType==AXI.WriteIssue64 and v[2].outputType==AXI.WriteResponse64, "Pulpino_AXIInterconnect: write should have type AXI.WriteIssue32->AXI.WriteResponse32, but is: "..tostring(v[2].inputType).."->"..tostring(v[2].outputType))

      slaveReadInst[k] = v[1]:instantiate("slaveRead"..k)
      slaveWriteInst[k] = v[2]:instantiate("slaveWrite"..k)
      table.insert( instanceList, slaveReadInst[k] )
      table.insert( instanceList, slaveWriteInst[k] )
    end
  end

  local axi_pkg = C.VerilogFile("generators/pulpino/axi/src/axi_pkg.sv")

  local fifo_v3 = C.VerilogFile("generators/pulpino/common_cells/src/fifo_v3.sv")
  local fifo_v2 = C.VerilogFile("generators/pulpino/common_cells/src/deprecated/fifo_v2.sv",fifo_v3)
  
  local axi_FanInPrimitive_Req = C.VerilogFile("generators/pulpino/axi_node/src/axi_FanInPrimitive_Req.sv")
  local axi_RR_Flag_Req = C.VerilogFile("generators/pulpino/axi_node/src/axi_RR_Flag_Req.sv")
  local axi_ArbitrationTree = C.VerilogFile("generators/pulpino/axi_node/src/axi_ArbitrationTree.sv",axi_FanInPrimitive_Req,axi_RR_Flag_Req)
  local axi_AR_allocator = C.VerilogFile("generators/pulpino/axi_node/src/axi_AR_allocator.sv",axi_ArbitrationTree)
  local axi_AW_allocator = C.VerilogFile("generators/pulpino/axi_node/src/axi_AW_allocator.sv")
  local axi_multiplexer = C.VerilogFile("generators/pulpino/axi_node/src/axi_multiplexer.sv")
  local axi_DW_allocator = C.VerilogFile("generators/pulpino/axi_node/src/axi_DW_allocator.sv",fifo_v2,axi_multiplexer)
  local axi_address_decoder_BW = C.VerilogFile("generators/pulpino/axi_node/src/axi_address_decoder_BW.sv")
  local axi_address_decoder_BR = C.VerilogFile("generators/pulpino/axi_node/src/axi_address_decoder_BR.sv")
  local axi_request_block = C.VerilogFile("generators/pulpino/axi_node/src/axi_request_block.sv",axi_AR_allocator,axi_AW_allocator,axi_DW_allocator,axi_address_decoder_BW,axi_address_decoder_BR)

  local axi_BW_allocator = C.VerilogFile("generators/pulpino/axi_node/src/axi_BW_allocator.sv",axi_pkg)
  local axi_BR_allocator = C.VerilogFile("generators/pulpino/axi_node/src/axi_BR_allocator.sv",axi_pkg)
  local axi_address_decoder_AR = C.VerilogFile("generators/pulpino/axi_node/src/axi_address_decoder_AR.sv")
  local axi_address_decoder_AW = C.VerilogFile("generators/pulpino/axi_node/src/axi_address_decoder_AW.sv")
  local axi_address_decoder_DW = C.VerilogFile("generators/pulpino/axi_node/src/axi_address_decoder_DW.sv")
  local axi_response_block = C.VerilogFile("generators/pulpino/axi_node/src/axi_response_block.sv",axi_BW_allocator,axi_BR_allocator,axi_address_decoder_AR,axi_address_decoder_AW,axi_address_decoder_DW)
  local axi_node = C.VerilogFile("generators/pulpino/axi_node/src/axi_node.sv",axi_request_block,axi_response_block)
  --print(axi_node)
  
  table.insert(instanceList, axi_node:instantiate("axi_node_inst"))
  
  local NOC = RM.moduleLambda("Pulpino_AXIInterconnect",SimpleNOCFns,instanceList)
  NOC.stateful = true

  NOC.makeSystolic = function()
    local s = C.automaticSystolicStub(NOC)

    local vstr = {NOC:vHeader()}

    for k,v in pairs(slaveReadInst) do table.insert(vstr,v:toVerilog()) end
    for k,v in pairs(slaveWriteInst) do table.insert(vstr,v:toVerilog()) end


    table.insert(vstr,[=[  axi_node #(.N_MASTER_PORT(]=]..#slavePorts..[=[),.N_SLAVE_PORT(]=]..NMaster..[=[),.AXI_ID_IN(11),.AXI_ID_OUT(12),.N_REGION(1)) axi_node_inst(.clk(CLK),.rst_n(~reset),.test_en_i(1'b0)
]=])

    if slavePorts~=nil then
      for axik, axiv in pairs(AXI.ReadAddressVSelect) do
        table.insert(vstr,",.master_"..axik.."_o({")
        for k,v in ipairs(slavePorts) do
          table.insert(vstr,slaveReadInst[k]:vInput()..axiv)
        end
        table.insert(vstr,"})\n")
      end

      table.insert(vstr,",.master_arready_i({")
      for k,v in ipairs(slavePorts) do
        table.insert(vstr,slaveReadInst[k]:vInputReady())
      end
      table.insert(vstr,"})\n")

      for axik, axiv in pairs(AXI.ReadDataVSelect(64)) do
        table.insert(vstr,",.master_"..axik.."_i({")
        for k,v in ipairs(slavePorts) do
          table.insert(vstr,slaveReadInst[k]:vOutput()..axiv)
        end
        table.insert(vstr,"})\n")
      end

      table.insert(vstr,",.master_rready_o({")
      for k,v in ipairs(slavePorts) do
        table.insert(vstr,slaveReadInst[k]:vOutputReady())
      end
      table.insert(vstr,"})\n")

      --------------------------  MASTER WRITE
      for axik, axiv in pairs(AXI.WriteIssueVSelect(64)) do
        table.insert(vstr,",.master_"..axik.."_o({")
        for k,v in ipairs(slavePorts) do
          table.insert(vstr,slaveWriteInst[k]:vInput()..axiv)
        end
        table.insert(vstr,"})\n")
      end

      table.insert(vstr,",.master_awready_i({")
      for k,v in ipairs(slavePorts) do
        table.insert(vstr,slaveWriteInst[k]:vInputReady().."[0]")
      end
      table.insert(vstr,"})\n")

      table.insert(vstr,",.master_wready_i({")
      for k,v in ipairs(slavePorts) do
        table.insert(vstr,slaveWriteInst[k]:vInputReady().."[1]")
      end
      table.insert(vstr,"})\n")

      for axik, axiv in pairs(AXI.WriteResponseVSelect(64)) do
        table.insert(vstr,",.master_"..axik.."_i({")
        for k,v in ipairs(slavePorts) do
          table.insert(vstr,slaveWriteInst[k]:vOutput()..axiv)
        end
        table.insert(vstr,"})\n")
      end

      table.insert(vstr,",.master_bready_o({")
      for k,v in ipairs(slavePorts) do
        table.insert(vstr,slaveWriteInst[k]:vOutputReady())
      end
      table.insert(vstr,"})\n")
    end


    ------------------------------------------------------------------------------------------

    -------------------- SLAVE READ
    for axik, axiv in pairs(AXI.ReadAddressVSelect) do
      table.insert(vstr,",.slave_"..axik.."_i({")

      if axik=="arid" then --hack
        assert(axiv=="[56:45]")
        axiv="[55:45]"
      end

      for i=NMaster-1,0,-1 do
        table.insert(vstr,"read"..J.sel(i>0,i,"").."_input"..axiv..J.sel(i>0,",",""))
      end
      table.insert(vstr,"})\n")
    end

    table.insert(vstr,",.slave_arready_o({")
    for i=NMaster-1,0,-1 do
      table.insert(vstr,"read"..J.sel(i>0,i,"").."_ready"..J.sel(i>0,",",""))
    end
    table.insert(vstr,"})\n")

    for axik, axiv in pairs(AXI.ReadDataVSelect(64)) do
      table.insert(vstr,",.slave_"..axik.."_o({")

      if axik=="rid" then --hack
        assert(axiv=="[78:67]")
        axiv="[77:67]"
      end

      for i=NMaster-1,0,-1 do
        table.insert(vstr,"read"..J.sel(i>0,i,"").."_output"..axiv..J.sel(i>0,",",""))
      end
      table.insert(vstr,"})\n")
    end

    table.insert(vstr,",.slave_rready_i({")
    for i=NMaster-1,0,-1 do
      table.insert(vstr,"read"..J.sel(i>0,i,"").."_ready_downstream"..J.sel(i>0,",",""))
    end
    table.insert(vstr,"})\n")

    --------------------- SLAVE WRITE
    for axik, axiv in pairs(AXI.WriteIssueVSelect(64)) do
      table.insert(vstr,",.slave_"..axik.."_i({")

      if axik=="awid" then --hack
        assert(axiv=="[56:45]")
        axiv="[55:45]"
      end

      for i=NMaster-1,0,-1 do
        local portName = 
        table.insert(vstr,"write"..J.sel(i>0,i,"").."_input"..axiv..J.sel(i>0,",",""))
      end
      table.insert(vstr,"})\n")
    end

    table.insert(vstr,",.slave_awready_o({")
    for i=NMaster-1,0,-1 do
      table.insert(vstr,"write"..J.sel(i>0,i,"").."_ready[0]"..J.sel(i>0,",",""))
    end
    table.insert(vstr,"})\n")

    table.insert(vstr,",.slave_wready_o({")
    for i=NMaster-1,0,-1 do
      table.insert(vstr,"write"..J.sel(i>0,i,"").."_ready[1]"..J.sel(i>0,",",""))
    end
    table.insert(vstr,"})\n")

    for axik, axiv in pairs(AXI.WriteResponseVSelect(64)) do

      if axik=="bid" then --hack
        assert(axiv=="[13:2]")
        axiv="[12:2]"
      end

      table.insert(vstr,",.slave_"..axik.."_o({")
      for i=NMaster-1,0,-1 do
        table.insert(vstr,"write"..J.sel(i>0,i,"").."_output"..axiv..J.sel(i>0,",",""))
      end
      table.insert(vstr,"})\n")
    end

    table.insert(vstr,",.slave_bready_i({")
    for i=NMaster-1,0,-1 do
      table.insert(vstr,"write"..J.sel(i>0,i,"").."_ready_downstream"..J.sel(i>0,",",""))
    end
    table.insert(vstr,"})\n")

    table.insert(vstr,[[,.cfg_START_ADDR_i({32'h30008000}),.cfg_END_ADDR_i({32'h3000E000}),.cfg_connectivity_map_i(2'b11),.cfg_valid_rule_i(1'b1));

]])
    
table.insert(vstr,[=[endmodule

]=])

    
    s:verilog(table.concat(vstr,""))
    return s
  end

  return NOC
end)

return Pulpino
