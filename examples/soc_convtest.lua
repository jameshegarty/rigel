local R = require "rigel"
local SOC = require "generators.soc"
local C = require "generators.examplescommon"
local harness = require "generators.harnessSOC"
local G = require "generators.core"
local RS = require "rigelSimple"
local T = require "types"
T.export()
local SDF = require "sdf"
local Zynq = require "generators.zynq"

local regs = SOC.axiRegs({},SDF{1,8192}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

ConvTop = G.Function{ "ConvTop", T.HandshakeTrigger, SDF{1,128*64},
  function(i)
    local readStream = G.AXIReadBurst{"frame_128.raw",{128,64},u(8),1,noc.read}(i)
    local O = G.Stencil{{-2,0,-2,0}}(readStream)
    local OC = G.Crop{{2,6,2,6}}(O)
    OC = G.Downsample{{4,4}}(OC)
    OC = G.Map{G.Map{G.Rshift{3}}}(OC)
    local OM = G.Map{G.Reduce{G.Add{R.Async}}}(OC)
    return G.AXIWriteBurst{"out/soc_convtest",noc.write}(OM)
  end}

-- extra cooldown: since we throw out last few rows, we aren't actually done when done bit is set...
harness({regs.start, ConvTop, regs.done},{cooldown=1500},{regs})
