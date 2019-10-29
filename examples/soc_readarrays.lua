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

local regs = SOC.axiRegs({},SDF{1,1024}):instantiate("regs")

local noc = Zynq.SimpleNOC(0,nil,{{regs.read,regs.write}} ):instantiate("ZynqNOC")
noc.extern=true

local OffsetModule = G.Module{ "OffsetModule", R.HandshakeTrigger,SDF{1,1024},
  function(i)
    local trig = G.Const{types.Uint(32),0}(i)
    print("TRIG",trig)
    local readStream = A.ReadArrays{types.uint(8),{128,64},G.Fread{"frame_128.raw"}}(trig)
    local offset = G.Add{200}(readStream)
    return G.AXIWriteBurst{"out/soc_readarrays",noc.write}(offset)
  end}

harness({regs.start, OffsetModule, regs.done},nil,{regs})
