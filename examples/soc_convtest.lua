local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
require "types".export()

regs = SOC.axiRegs{}:instantiate()

ConvTop = G.Module{
  function(i)
    local readStream = G.AXIReadBurst{"frame_128.raw",{128,64},u(8),2}(i)
    local O = G.HS{G.Stencil{{2,0,2,0}}}(readStream)
    local OC = G.HS{G.Crop{{2,0,2,0}}}(O)
    OC = G.HS{G.Map{G.Map{G.Rshift{3}}}}(OC)
    local OM = G.HS{G.Map{G.Reduce{G.Add}}}(OC)
    return G.AXIWriteBurst{"out/soc_convtest"}(OM)
  end}

harness{regs.start, ConvTop, regs.done}
