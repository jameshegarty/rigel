local R = require "rigel"
local SOC = require "generators.soc"
local C = require "generators.examplescommon"
local harness = require "generators.harnessSOC"
local G = require "generators.core"
local RS = require "rigelSimple"
local SDF = require "sdf"
local types = require "types"
require "types".export()
local Zynq = require "generators.zynq"
local RM = require "generators.modules"

local regs = SOC.axiRegs({{"offset",RM.reg(u(32),200)}},SDF{1,1024}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local AddReg = G.Function{ "AddReg", types.rv(types.Par(u(8))), SDF{1,1},
  function(i) return G.Add(i,G.RemoveMSBs{24}(RM.Storv(regs.offset)(G.ValueToTrigger(i)))) end}

harness({
  regs.start,
  SOC.readBurst("frame_128.raw",128,64,u(8),8,true,nil,noc.read),
  G.Map{AddReg},
  SOC.writeBurst("out/soc_regin",128,64,u(8),8,1,true,noc.write),
  regs.done},nil,{regs})
