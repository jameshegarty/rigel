local R = require "rigel"
local SOC = require "generators.soc"
local C = require "generators.examplescommon"
local harness = require "generators.harnessSOC"
local G = require "generators.core"
local RS = require "rigelSimple"
local types = require "types"
local SDF = require "sdf"
types.export()
local Zynq = require "generators.zynq"
local RM = require "generators.modules"

local regs = SOC.axiRegs({{"startCnt",RM.reg(u32,0,true)},{"endCnt",RM.reg(u32,0,true)}},SDF{1,8192}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local RegInOut = G.Function{ "RegInOut", types.HandshakeTrigger, SDF{1,1},
  function(i)
    local o = G.AXIReadBurstSeq{"frame_128.raw",{128,64},u(8),1,noc.read}(i)
    o = C.tokenCounterReg(o.type,regs.startCnt,128*64*2048)(o)
    o = G.Fmap{C.downsampleSeq( u8, 128, 64, 1, 2, 2)}(o)
    o = C.tokenCounterReg(o.type,regs.endCnt,128*64*2048)(o)
    return G.AXIWriteBurstSeq{"out/soc_tokencounter",{64,32},1,noc.write}(o)
  end}

harness({regs.start,RegInOut,regs.done},nil,{regs})
