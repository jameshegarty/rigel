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

R.MONITOR_FIFOS = true

local regs = SOC.axiRegs({},SDF{1,1024}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}} ):instantiate("ZynqNOC")
noc.extern=true

local OffsetModule = G.Function{ "OffsetModule", R.HandshakeTrigger,
  function(i)
    local readStream = G.AXIReadBurst{ "frame_128.raw", {128,64}, u(8), 8, noc.read }(i)
    local offset = G.Map{G.Add{200}}(readStream)
    return G.AXIWriteBurst{"out/soc_simple",noc.write}(offset)
  end}

harness({regs.start, OffsetModule, regs.done},nil,{regs})
