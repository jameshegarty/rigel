local R = require "rigel"
R.export()
require "generators".export()
local harness = require "harnessSOC"
local SOC = require "soc"
local C = require "examplescommon"
local SDF = require "sdf"
require "types".export()

regs = SOC.axiRegs{}:instantiate(SDF{1,1024})

local W,H = 128,64

addrGen = Module{function(inp)
  local x, y = Index{0}(Index{0}(inp)), Index{1}(Index{0}(inp))
  local resx = AddMSBs{16}(x)
  local resy = Mul( Sub(c(H-1,u(32)),AddMSBs{16}(y)),c(W/8,u(32)) )
  return Add(resx,resy)
end}

harness{
  regs.start,
  C.triggerUp( (W*H)/8 ),
  HS{PosSeq{{W/8,H},1}},
  HS{addrGen},
  SOC.read("frame_128.raw",128*64,ar(u(8),8)),
  SOC.writeBurst("out/soc_flip",128,64,u(8),8),
  regs.done}
