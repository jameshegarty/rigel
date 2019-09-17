local R = require "rigel"
R.export()
local SOC = require "generators.soc"
local harness = require "generators.harnessSOC"
local RS = require "rigelSimple"
local C = require "generators.examplescommon"
local SDF = require "sdf"
require "generators.core".export()
local types = require "types"
types.export()
local Zynq = require "generators.zynq"

local ConvWidth = 4
local ConvRadius = ConvWidth/2

local inSize = { 1920, 1080 }
local padSize = { 1920+16, 1080+3 }

local regs = SOC.axiRegs({},SDF{1,padSize[1]*padSize[2]}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local conv = Generator{ types.rv(types.Par(ar(u(8),ConvWidth,ConvWidth))),
                        types.rv(types.Par(u8)),
function(inp)
  inp = AddMSBs{24}(inp)
  local coeff = c({4, 14, 14,  4,
                   14, 32, 32, 14,
                   14, 32, 32, 14,
                   4, 14, 14,  4},ar(u(32),ConvWidth,ConvWidth))
  local z = Zip(inp,coeff)
  local out = Mul(z)
  local res = Reduce{Add{R.Async}}(out)
  return RemoveMSBs{24}(Rshift{8}(res))
end}

harness({
  regs.start,
  AXIReadBurst{"1080p.raw",{1920,1080},u8,1,noc.read},
  Pad{{8,8,2,1}},
--  RS.HS(C.print(ar(u(8),1))),
  Stencil{{-3,0,-3,0}},
  conv,
  Crop{{9,7,3,0}},
  AXIWriteBurst{"out/soc_convgen",noc.write},
  regs.done},nil,{regs})
