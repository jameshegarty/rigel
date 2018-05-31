local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
require "types".export()

regs = SOC.axiRegsN(4,0):instantiate()

harness{
  regs.start,
  SOC.readBurst("frame_128.raw",128,64,u(8),8),
  G.HS{G.Map{C.plus100(u(8))}},
  G.HS{G.Map{C.plus100(u(8))}},
  SOC.writeBurst("out/soc_simple",128,64,u(8),8),
  regs.done}
