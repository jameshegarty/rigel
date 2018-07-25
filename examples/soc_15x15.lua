local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
local RM = require "modules"
require "types".export()
local types = require "types"

regs = SOC.axiRegs{}:instantiate()

------------
inp = R.input( types.uint(8) )
a = R.apply("a", C.plus100(types.uint(8)), inp)
b = R.apply("b", C.plus100(types.uint(8)), a)
p200 = RM.lambda( "p200", inp, b )
------------
hsfn = RM.makeHandshake(p200)

harness{
  regs.start,
  SOC.readBurst("15x15.raw",15,15,u(8),0),
  hsfn,
  SOC.writeBurst("out/soc_15x15",15,15,u(8),0),
  regs.done}
