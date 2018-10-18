local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
local types = require "types"
local SDF = require "sdf"
types.export()

regs = SOC.axiRegs{}:instantiate()

OffsetModule = G.Module{ "OffsetModule", R.HandshakeTrigger,
  function(i)
    print("I",i.type,i)
    local readStream = G.AXIReadBurstSeq{"frame_128.raw",{128,64},u(8),8}(i)
    local offset = G.HS{G.Sort{G.GT}}(readStream)
    return G.AXIWriteBurstSeq{"out/soc_sort",{128,64},8}(offset)
  end}

--print(OffsetModule)
--print(OffsetModule:toVerilog())

harness{regs.start, OffsetModule, regs.done}
