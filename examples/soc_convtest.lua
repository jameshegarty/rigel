local R = require "rigel"
local SOC = require "generators.soc"
local C = require "generators.examplescommon"
local harness = require "generators.harnessSOC"
local G = require "generators.core"
local RS = require "rigelSimple"
require "types".export()
local SDF = require "sdf"
local Zynq = require "generators.zynq"

local regs = SOC.axiRegs({},SDF{1,8192}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

ConvTop = G.Module{
  function(i)
    local readStream = G.AXIReadBurst{"frame_128.raw",{128,64},u(8),1,noc.read}(i)
    local O = G.Stencil{{-2,0,-2,0}}(readStream)
    local OC = G.Crop{{2,6,2,6}}(O)
    OC = G.Downsample{{4,4}}(OC)
    OC = G.Rshift{3}(OC)
    local OM = G.Reduce{G.Add{R.Async}}(OC)
    return G.AXIWriteBurst{"out/soc_convtest",noc.write}(OM)
  end}

harness({regs.start, ConvTop, regs.done},nil,{regs})
