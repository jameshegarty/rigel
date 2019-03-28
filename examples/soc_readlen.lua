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


-- this is an example of a simple runtime configurable DMA that loads 64bits/cycle at a configurable address & length

noc = Zynq.SimpleNOC():instantiate("ZynqNOC")
noc.extern=true
local regs = SOC.axiRegs({readAddress={u(32),0x30008000},len={u32,(128*64)/8}},SDF{1,(128/8)*64},noc.readSource,noc.readSink,noc.writeSource,noc.writeSink):instantiate("regs")

local Len = Uniform(regs.len)
Len:addProperty( Len:ge(1) )
Len:addProperty( Len:lt(math.pow(2,16)) )

-- DANGEROUS HACK
regs.module.functions.start.sdfOutput = SDF{1,Len}
regs.module.functions.done.sdfInput = SDF{1,Len}

-- This is the actual DMA
ReadLenDMA = G.Module{ "ReadLenDMA", HandshakeTrigger, SDF{1,Len},
  function(trig)
    trig = C.triggerUp(regs.len)(trig)
    local addrStream = G.HS{RM.counter(u32,regs.len)}(trig)
    --addrStream = G.HS{G.Print{"AddrIn"}}(addrStream)
    return SOC.read("frame_128.raw",128*64,ar(u8,8),noc.read)(addrStream)
  end}

AddAddr = G.Module{"AddAddr",function(i) return R.concat{RM.counter(u32,regs.len)(),i} end}
WriteLenDMA = G.Module{ "WriteLenDMA", Handshake(ar(u8,8)),
  function(i)
    local addrStream = G.HS{AddAddr}(i)
    local bresp = SOC.write("out/soc_readlen",regs.len,1,ar(u8,8),0,true,noc.write)(addrStream)
    return RM.triggerCounter(Len)(bresp)
  end}

TestDMA = C.linearPipeline({ReadLenDMA,G.HS{G.Map{C.plusConst(u8,200)}},WriteLenDMA},"TestDMA")
print(TestDMA)

-- hack
TestDMA.globalMetadata.MAXI0_write_W = 128
TestDMA.globalMetadata.MAXI0_write_H = 64
TestDMA.globalMetadata.MAXI0_write_bitsPerPixel = 8

harness({regs.start, TestDMA, regs.done},{cycles=1124},{regs})
