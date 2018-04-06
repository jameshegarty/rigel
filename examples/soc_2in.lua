local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local RS = require "rigelSimple"
local RM = require "modules"
require "types".export()

local inp = R.input(R.HandshakeTrigger)
local a = SOC.readBurst("frame_128.raw",128,64,u(8),8)(inp)
a = RS.HS(C.cast(b(64),u(64)))(a)
local bb = SOC.readBurst("frame_128_2.raw",128,64,u(8),8)(inp)
bb = RS.HS(C.cast(b(64),u(64)))(bb)
local out = RS.fanIn{a,bb}
out = RS.HS(C.sum(u(64),u(64),u(64)))(out)
out = RS.HS(C.cast(u(64),b(64)))(out)
out = SOC.writeBurst("out/soc_2in",128,64,u(8),8)(out)

harness(RM.lambda("Top",inp,out))
