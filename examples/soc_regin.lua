local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
local SDF = require "sdf"
require "types".export()

local Regs = SOC.axiRegs{offset={u(32),200}}
regs = Regs:instantiate(SDF{1,1024})

print("REGS",Regs.offset)

local AddReg = G.Module{function(i) return G.Add(i,G.RemoveMSBs{24}(Regs.offset)) end}

harness{
  regs.start,
  SOC.readBurst("frame_128.raw",128,64,u(8),8),
  G.HS{G.Map{AddReg}},
  SOC.writeBurst("out/soc_regin",128,64,u(8),8),
  regs.done}
