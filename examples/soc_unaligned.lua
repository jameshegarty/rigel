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
local regs = SOC.axiRegs({},SDF{1,128},noc.readSource,noc.readSink,noc.writeSource,noc.writeSink):instantiate("regs")

OffsetModule = G.Module{ "OffsetModule", R.HandshakeTrigger,
  function(i)
    local tstream = G.TriggerBroadcast{128}(i)
    local addrStream = G.HS{G.PosSeq{{128,1},0}}(tstream)
    addrStream = G.HS{G.Index{0}}(addrStream)
    addrStream = G.HS{G.AddMSBs{16}}(addrStream)
    addrStream = G.HS{G.Add{3}}(addrStream)
    local readStream = G.AXIRead{"frame_128.raw",128*64,noc.read}(addrStream)
    return G.AXIWriteBurstSeq{"out/soc_unaligned",{128,1},0,noc.write}(readStream)
  end}

harness({regs.start, OffsetModule, regs.done},nil,{regs})
