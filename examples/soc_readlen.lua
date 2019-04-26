local R = require "rigel"
local G = require "generators"
local SOC = require "soc"
local harness = require "harnessSOC"
require "types".export()
local SDF = require "sdf"
local RM = require "modules"
local Zynq = require "zynq"
local C = require "examplescommon"
local Uniform = require "uniform"
local AXI = require "axi"

-- this is an example of a simple runtime configurable DMA that loads 64bits/cycle at a configurable address & length

local Regs = SOC.axiRegs({readAddress={u(32),0x30008000},writeAddress={u(32),0x30008000+(128*64)},len={u32,(128*64)/8}},SDF{1,(128/8)*64})
local regs = Regs:instantiate("regs")

local Len = Uniform(regs.len)
Len:addProperty( Len:ge(1) )
Len:addProperty( Len:lt(math.pow(2,16)) )

-- DANGEROUS HACK
regs.module.functions.start.sdfInput = SDF{1,Len}
regs.module.functions.start.sdfOutput = SDF{1,Len}
regs.module.functions.done.sdfInput = SDF{1,Len}
regs.module.functions.done.sdfOutput = SDF{1,Len}

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local WriteAddress = Uniform(regs.writeAddress)
WriteAddress:addProperty( WriteAddress:eq(0x30008000+(128*64)) )

-- This is the actual DMA
ReadLenDMA = G.Module{ "ReadLenDMA", HandshakeTrigger, SDF{1,Len},
  function(trig)
    trig = C.triggerUp(regs.len)(trig)
    local addrStream = G.HS{RM.counter(u32,regs.len)}(trig)
    return SOC.read("frame_128.raw",128*64,ar(u8,8),noc.read,nil,regs.readAddress)(addrStream)
  end}

AddAddr = G.Module{"AddAddr",function(i) return R.concat{RM.counter(u32,regs.len)(),i} end}
WriteLenDMA = G.Module{ "WriteLenDMA", Handshake(ar(u8,8)),
  function(i)
    local addrStream = G.HS{AddAddr}(i)
    local bresp = SOC.write( "out/soc_readlen", regs.len, 1, ar(u8,8), 0, true, noc.write, regs.writeAddress )(addrStream)
    return RM.triggerCounter(Len)(bresp)
  end}

TestDMA = C.linearPipeline({ReadLenDMA,G.HS{G.Map{C.plusConst(u8,200)}},WriteLenDMA},"TestDMA")

-- hack
TestDMA.globalMetadata[noc.write.name.."_write_W"] = 128
TestDMA.globalMetadata[noc.write.name.."_write_H"] = 64
TestDMA.globalMetadata[noc.write.name.."_write_bitsPerPixel"] = 8

--for k,v in pairs(AXI.ReadAddressVSelect) do print("readAddress",k,v) end
--for k,v in pairs(AXI.ReadDataVSelect(64)) do print("readData",k,v) end
--for k,v in pairs(AXI.WriteIssueVSelect(64)) do print("writeIssue",k,v) end
--for k,v in pairs(AXI.WriteResponseVSelect(64)) do print("writeResponse",k,v) end


--local Top=C.linearPipeline({regs.start, TestDMA, regs.done},"Top",nil,{regs})

--print(Top)

--harness(Top,{cycles=1124})
harness({regs.start, TestDMA, regs.done},{cycles=1124},{regs})
