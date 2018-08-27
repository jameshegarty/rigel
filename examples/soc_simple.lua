local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
require "types".export()

regs = SOC.axiRegs{}:instantiate()

OffsetModule = G.Module{
  function(i)
    local readStream = G.AXIReadBurst{"frame_128.raw",{128,64},u(8),8}(i)
    local offset = G.HS{G.Map{G.Add{200}}}(readStream)
    return G.AXIWriteBurst{"out/soc_simple",{128,64} ,u(8),8}(offset)
  end}

harness{regs.start, OffsetModule, regs.done}
