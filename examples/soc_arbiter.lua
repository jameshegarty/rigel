local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
local types = require "types"
local SDF = require "sdf"
types.export()
local Zynq = require "zynq"

noc = Zynq.SimpleNOC():instantiate("ZynqNOC")
noc.extern=true
local regs = SOC.axiRegs({},SDF{1,1024},noc.readSource,noc.readSink,noc.writeSource,noc.writeSink):instantiate("regs")

local OffsetModule = G.Module{ "OffsetModule", R.HandshakeTrigger,
  function(i)
    local readStream = G.AXIReadBurst{"frame_128.raw",{128,64},u(8),8,noc.read}(i)
    local rb = G.FanOut{2}(readStream)
    local rb0 = G.HS{G.Crop{{0,96,0,0}}}(rb[0])
    local rb1 = G.HS{G.Crop{{96,0,0,0}}}(rb[1])
    local arb = G.Arbitrate(R.concatArray2d("cca2",{G.StripFramed(rb0),G.StripFramed(rb1)},2))
    return G.AXIWriteBurstSeq{"out/soc_arbiter",{64,64},8,noc.write}(arb)
  end}


harness({regs.start, OffsetModule, regs.done},nil,{regs})
