local R = require "rigel"
R.export()
local SOC = require "soc"
local harness = require "harnessSOC"
local RS = require "rigelSimple"
local C = require "examplescommon"
require "generators".export()
require "types".export()
local SDF = require "sdf"

local ConvWidth = 4
local ConvRadius = ConvWidth/2

inSize = { 1920, 1080 }
padSize = { 1920+16, 1080+3 }

regs = SOC.axiRegs({
  coeffs={ar(u(32),ConvWidth,ConvWidth),
          {4, 14, 14,  4,
           14, 32, 32, 14,
           14, 32, 32, 14,
           4, 14, 14,  4}}},SDF{1,padSize[1]*padSize[2]}):instantiate()

local conv = Module{ ar(u(8),ConvWidth,ConvWidth),
function(inp)
  inp = Map{AddMSBs{24}}(inp)
  local z = Zip(inp,regs.module.coeffs)
  local out = Map{Mul}(z)
  local res = Reduce{Add}(out)
  return RemoveMSBs{24}(Rshift{8}(res))
end}

harness{
  regs.start,
  SOC.readBurst("1080p.raw",1920,1080,u(8),1),
  HS{Pad{inSize,1,{8,8,2,1}}},
  HS{Linebuffer{padSize,1,{3,0,3,0}}},
  HS{Map{conv}},
  HS{CropSeq{padSize,1,{9,7,3,0}}},
  SOC.writeBurst("out/soc_convgenTaps",1920,1080,u(8),1),
  regs.done}
