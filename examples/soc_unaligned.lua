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
    local tstream = G.TriggerBroadcast{128}(i)
    local addrStream = G.HS{G.PosSeq{{128,1},0}}(tstream)
    addrStream = G.HS{G.Index{0}}(addrStream)
    addrStream = G.HS{G.AddMSBs{16}}(addrStream)
    addrStream = G.HS{G.Add{3}}(addrStream)
    --addrStream = G.HS{G.Print}(addrStream)
    local readStream = G.AXIRead{"frame_128.raw",128*64}(addrStream)
    return G.AXIWriteBurstSeq{"out/soc_unaligned",{128,1},0}(readStream)
  end}

--print(OffsetModule)
--print(OffsetModule:toVerilog())

harness{regs.start, OffsetModule, regs.done}
