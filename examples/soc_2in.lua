local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local RS = require "rigelSimple"
local RM = require "modules"
require "types".export()

local inp = R.input(R.HandshakeTrigger)
local inp0, inp1 = RS.fanOut{input=inp,branches=2}
local a = SOC.readBurst("frame_128.raw",128,64,u(8),8)(inp0)
--a = C.fifo(b(64),1024)(a)
a = RS.HS(C.cast(b(64),ar(u(8),8)))(a)
local bb = SOC.readBurst("frame_128_inv.raw",128,64,u(8),8)(inp1)
--bb = C.fifo(b(64),1024)(bb)
bb = RS.HS(C.cast(b(64),ar(u(8),8)))(bb)
local out = RS.fanIn{a,bb}
out = RS.HS(RM.SoAtoAoS(8,1,{u(8),u(8)}))(out)
out = RS.HS(RM.map(C.sum(u(8),u(8),u(8)),8))(out)
out = RS.HS(C.cast(ar(u(8),8),b(64)))(out)
out = SOC.writeBurst("out/soc_2in",128,64,u(8),8)(out)

harness(RM.lambda("Top",inp,out))
