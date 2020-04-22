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
local A = require "generators.accessors"

R.Z3_FIFOS = true

local regs = SOC.axiRegs({},SDF{1,1024}):instantiate("regs")

local noc = Zynq.SimpleNOC(0,nil,{{regs.read,regs.write}} ):instantiate("ZynqNOC")
noc.extern=true

local first,flen = string.find(arg[0],"%d+")
local cyc = tonumber(string.sub(arg[0],first,flen))

local OffsetModule = G.Function{ "OffsetModule", R.HandshakeTrigger, SDF{1,1024/cyc},
  function(i)
    local trig = G.Const{types.Uint(32),0}(i)
    local readStream = A.ReadArrays{types.uint(8),{128,64},G.Fread{"frame_128.raw"}}(trig)
    local offset = G.Map{G.Add{200}}(readStream)
    return G.AXIWriteBurst{"out/soc_readarrays_"..tostring(cyc),noc.write}(offset)
  end}

harness({regs.start, OffsetModule, regs.done},nil,{regs})
