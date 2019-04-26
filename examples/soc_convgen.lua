local R = require "rigel"
R.export()
local SOC = require "soc"
local harness = require "harnessSOC"
local RS = require "rigelSimple"
local C = require "examplescommon"
local SDF = require "sdf"
require "generators".export()
require "types".export()
local Zynq = require "zynq"

local ConvWidth = 4
local ConvRadius = ConvWidth/2

local inSize = { 1920, 1080 }
local padSize = { 1920+16, 1080+3 }

local regs = SOC.axiRegs({},SDF{1,padSize[1]*padSize[2]}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local conv = Module{ ar(u(8),ConvWidth,ConvWidth),
function(inp)
  inp = Map{AddMSBs{24}}(inp)
  local coeff = c({4, 14, 14,  4,
                   14, 32, 32, 14,
                   14, 32, 32, 14,
                   4, 14, 14,  4},ar(u(32),ConvWidth,ConvWidth))
  local z = Zip(inp,coeff)
  local out = Map{Mul}(z)
  local res = Reduce{Add}(out)
  return RemoveMSBs{24}(Rshift{8}(res))
end}

harness({
  regs.start,
  SOC.readBurst("1080p.raw",1920,1080,u(8),1,nil,nil,noc.read),
  HS{Pad{inSize,1,{8,8,2,1}}},
--  RS.HS(C.print(ar(u(8),1))),
  HS{Linebuffer{padSize,1,{3,0,3,0}}},
  HS{Map{conv}},
  HS{CropSeq{padSize,1,{9,7,3,0}}},
  SOC.writeBurst("out/soc_convgen",1920,1080,u(8),1,nil,noc.write),
  regs.done},nil,{regs})
