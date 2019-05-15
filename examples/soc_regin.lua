local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
local SDF = require "sdf"
require "types".export()
local Zynq = require "zynq"

local regs = SOC.axiRegs({offset={u(32),200}},SDF{1,1024}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local AddReg = G.Module{u(8),function(i) return G.Add(i,G.RemoveMSBs{24}(regs.offset())) end}

harness({
  regs.start,
  SOC.readBurst("frame_128.raw",128,64,u(8),8,nil,nil,noc.read),
  G.HS{G.Map{AddReg}},
  SOC.writeBurst("out/soc_regin",128,64,u(8),8,nil,noc.write),
  regs.done},nil,{regs})
