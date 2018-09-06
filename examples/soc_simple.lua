local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
local types = require "types"
types.export()

regs = SOC.axiRegs{}:instantiate()

OffsetModule = G.Module{ "OffsetModule", R.HandshakeTrigger,
  function(i)
    local readStream = G.AXIReadBurst{"frame_128.raw",{128,64},u(8),8}(i)
    local offset = G.HS{G.Map{G.Add{200}}}(readStream)
    return G.AXIWriteBurst{"out/soc_simple"}(offset)
  end}

--print(OffsetModule)
--print(OffsetModule:toVerilog())

harness{regs.start, OffsetModule, regs.done}
