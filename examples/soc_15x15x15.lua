local R = require "rigel"
local SOC = require "generators.soc"
local C = require "generators.examplescommon"
local harness = require "generators.harnessSOC"
local G = require "generators.core"
local RS = require "rigelSimple"
local RM = require "generators.modules"
require "types".export()
local types = require "types"
local SDF = require "sdf"
local Zynq = require "generators.zynq"

regs = SOC.axiRegs({},SDF{1,240}):instantiate("regs")
noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

------------
local p200 = G.Function{"p200", types.rv(types.Par(types.uint(8))), SDF{1,1},
  function(inp) return C.plus100(types.uint(8))(C.plus100(types.uint(8))(inp)) end}
------------
--hsfn = RM.makeHandshake(p200)

harness({
  regs.start,
  G.AXIReadBurst{"15x15.raw",{15,15},u(8),15,noc.read},
  G.Map{p200},
  G.AXIWriteBurst{"out/soc_15x15x15",noc.write},
  regs.done},{cycles=800},{regs})
