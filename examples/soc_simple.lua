local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessLL"
local RS = require "rigelSimple"
require "types".export()

print(i,u,b)
harness{SOC.axiBurstReadN("frame_128.raw",(128*64)/8,0), RS.HS(C.cast(b(64),u(64))), RS.HS(C.plus100(u(64))), RS.HS(C.cast(u(64),b(64))), SOC.axiBurstWriteN("out/soc_simple",(128*64)/8,0)}
