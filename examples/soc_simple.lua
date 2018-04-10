local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local RS = require "rigelSimple"
require "types".export()

harness{
  SOC.readBurst("frame_128.raw",128,64,u(8),8),
  RS.HS(C.cast(b(64),u(64))),
  RS.HS(C.plus100(u(64))),
  RS.HS(C.cast(u(64),b(64))),
  SOC.writeBurst("out/soc_simple",128,64,u(8),8)}
