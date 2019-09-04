local R = require "rigel"
local SOC = require "generators.soc"
local C = require "generators.examplescommon"
local harness = require "generators.harnessSOC"
local G = require "generators.core"
local RS = require "rigelSimple"
local types = require "types"
types.export()
local SDF = require "sdf"
local Zynq = require "generators.zynq"

local regs = SOC.axiRegs({},SDF{1,128*64}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local OffsetModule = G.Module{ "OffsetModule", R.HandshakeTrigger,
  function(i)
    local readStream = G.AXIReadBurst{"frame_128.raw",{128,64},u(8),0,noc.read}(i)
    local rs = G.FanOut{2}(readStream)
    local rs0 = G.FIFO{128}(rs[0])
    --print("RS)",rs0)
    local rs1 = G.FIFO{128}(rs[1])
    local filt = G.GT{192}(rs1)
    --print("FILT",filt.type)
    local finp = G.Zip(G.FanIn(rs0,filt))

    -- 368
    local offset = G.Filter{{368,8192}}(finp)

    offset = G.ClampToSize{{368,1}}(offset) -- hack
    --return G.AXIWriteBurstSeq{"out/soc_filterseq",{368,1},0,noc.write}(offset)
    return G.AXIWriteBurst{"out/soc_filterseq",noc.write}(offset)
  end}

harness({regs.start, OffsetModule, regs.done},nil,{regs})
