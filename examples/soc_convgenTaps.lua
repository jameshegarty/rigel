local R = require "rigel"
R.export()
local SOC = require "generators.soc"
local harness = require "generators.harnessSOC"
local RM = require "generators.modules"
local C = require "generators.examplescommon"
require "generators.core".export()
local T = require "types"
T.export()
local SDF = require "sdf"
local Zynq = require "generators.zynq"

local ConvWidth = 4
local ConvRadius = ConvWidth/2

local inSize = { 1920, 1080 }
local padSize = { 1920+16, 1080+3 }

local regs = SOC.axiRegs({
  {"coeffs",RM.reg(ar(u(32),ConvWidth,ConvWidth),
          {4, 14, 14,  4,
           14, 32, 32, 14,
           14, 32, 32, 14,
           4, 14, 14,  4})}},SDF{1,padSize[1]*padSize[2]}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true


local conv = Generator{ T.rv(T.Par(ar(u(8),ConvWidth,ConvWidth))),
                        T.rv(T.Par(u8)),
function(inp)
  inp = AddMSBs{24}(inp)
  local z = Zip(inp,RM.Storv(regs.coeffs)(ValueToTrigger(inp)))
  local out = Mul(z)
  local res = Reduce{Add{R.Async}}(out)
  return RemoveMSBs{24}(Rshift{8}(res))
end}

harness({
  regs.start,
  AXIReadBurst{"1080p.raw",{1920,1080},u(8),1,noc.read},
  Pad{{8,8,2,1}},
  Stencil{{-3,0,-3,0}},
  conv,
  Crop{{9,7,3,0}},
  AXIWriteBurst{"out/soc_convgenTaps",noc.write},
  regs.done},nil,{regs})
