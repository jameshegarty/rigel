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

local regs = SOC.axiRegs({},SDF{1,1024}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

OffsetModule = G.Function{ "OffsetModule", R.HandshakeTrigger, SDF{1,1},
  function(i)
    local readStream = G.AXIReadBurstSeq{"frame_128.raw",{128,64},u(8),8,noc.read}(i)
    local offset = G.Sort{G.GT}(readStream)
    return G.AXIWriteBurstSeq{"out/soc_sort",{128,64},8,noc.write}(offset)
  end}

harness({regs.start, OffsetModule, regs.done},nil,{regs})
