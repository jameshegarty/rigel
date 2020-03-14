local R = require "rigel"
local SOC = require "generators.soc"
local C = require "generators.examplescommon"
local harness = require "generators.harnessSOC"
local G = require "generators.core"
local RS = require "rigelSimple"
local types = require "types"
local SDF = require "sdf"
types.export()
local Zynq = require "generators.zynq"

local regs = SOC.axiRegs({},SDF{1,128}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

OffsetModule = G.Function{ "OffsetModule", R.HandshakeTrigger, SDF{1,1}, 
  function(i)
    local tstream = G.TriggerBroadcast{128}(i)
    local addrStream = G.PosSeq{{128,1},0}(tstream)
    addrStream = G.Index{0}(addrStream)
    addrStream = G.AddMSBs{16}(addrStream)
    addrStream = G.Add{3}(addrStream)
    local readStream = G.AXIRead{"frame_128.raw",128*64,noc.read,types.U(8)}(addrStream)
    return G.AXIWriteBurstSeq{"out/soc_unaligned",{128,1},0,noc.write}(readStream)
  end}

harness({regs.start, OffsetModule, regs.done},nil,{regs})
