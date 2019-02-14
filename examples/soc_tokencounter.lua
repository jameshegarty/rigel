local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
local types = require "types"
local SDF = require "sdf"
types.export()

local Regs = SOC.axiRegs({startCnt={u32,0,"input"},endCnt={u32,0,"input"}},SDF{1,8192})
regs = Regs:instantiate()

local RegInOut = G.Module{
  function(i)
    local o = G.AXIReadBurstSeq{"frame_128.raw",{128,64},u(8),1}(i)
    o = C.tokenCounterReg(o.type,Regs.startCnt,128*64*2048)(o)
    o = G.HS{C.downsampleSeq( u8, 128, 64, 1, 2, 2)}(o)
    o = C.tokenCounterReg(o.type,Regs.endCnt,128*64*2048)(o)
    print("OT",o.type)
    return G.AXIWriteBurstSeq{"out/soc_tokencounter",{64,32},1}(o)
  end}

harness{regs.start,RegInOut,regs.done}
