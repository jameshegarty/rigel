local R = require "rigel"
local SOC = require "generators.soc"
local C = require "generators.examplescommon"
local harness = require "generators.harnessSOC"
local G = require "generators.core"
local RS = require "rigelSimple"
local RM = require "generators.modules"
local types = require "types"
local SDF = require "sdf"
types.export()
local Zynq = require "generators.zynq"

-- this test relies on the timing w/o fifos
R.AUTO_FIFOS = false

local regs = SOC.axiRegs({},SDF{1,1024}):instantiate("regs")
local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local OffsetModule = G.Function{ "OffsetModule", R.HandshakeTrigger, SDF{1,1024},
  function(i)
    local readStream = G.AXIReadBurstSeq{"frame_128.raw",{128,64},u(8),8,noc.read}(i)
    local rb = G.FanOut{2}(readStream)
    local ty = types.rv(types.Par(types.array2d(u8,8)))
    local rb0 = G.Fmap{G.CropSeq{{0,96,0,0},{128,64},8,ty,SDF{1,1}}}(rb[0])
    rb0 = G.FIFO{1}(rb0)
    local rb1 = G.Fmap{G.CropSeq{{96,0,0,0},{128,64},8,ty,SDF{1,1}}}(rb[1])
    rb1 = G.FIFO{1}(rb1)
    local arb = G.Arbitrate{R.Unoptimized}(R.concatArray2d("cca2",{rb0,rb1},2))
    return G.AXIWriteBurstSeq{"out/soc_arbiter",noc.write,{64,64},8}(arb)
  end}

harness({regs.start, OffsetModule, regs.done},nil,{regs})
