local R = require "rigel"
R.export()
require "generators.core".export()
local harness = require "generators.harnessSOC"
local SOC = require "generators.soc"
local C = require "generators.examplescommon"
local SDF = require "sdf"
local Zynq = require "generators.zynq"
local T = require "types"
T.export()

local regs = SOC.axiRegs({},SDF{1,1024}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local W,H = 128,64

addrGen = Generator{ SDF{1,1}, T.rv(T.Par(T.tuple{T.uint(16),T.uint(16)})), T.rv(T.Par(u(32))),
function(inp)
  print("ADDRGEN",inp.type)
  local x, y = Index{0}(inp), Index{1}(inp)
  local resx = AddMSBs{16}(x)
  local resy = Mul( Sub(c(H-1,u(32)),AddMSBs{16}(y)),c(W/8,u(32)) )
  return Add(resx,resy)
end}

print(addrGen)

harness({
  regs.start,
  C.triggerUp( (W*H)/8 ),
  PosSeq{{W/8,H},0},
  addrGen,
  SOC.read( "frame_128.raw", 128*64,ar(u(8),8), noc.read),
  SOC.writeBurst("out/soc_flip",128,64,u(8),8,1,nil,noc.write),
  regs.done},nil,{regs})
