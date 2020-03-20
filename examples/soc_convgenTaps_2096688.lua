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
local P = require "params"
local G = require "generators.core"
local Uniform = require "uniform"

local ConvWidth = 4
local ConvRadius = ConvWidth/2

local cycles = tonumber(string.match(arg[0],"%d+"))
print("CYCLES",cycles)

local regs = SOC.axiRegs({
  {"coeffs",RM.reg(ar(u(32),ConvWidth,ConvWidth),
          {4, 14, 14,  4,
           14, 32, 32, 14,
           14, 32, 32, 14,
           4, 14, 14,  4})}},SDF{1,cycles}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local ts=""
if terralib~=nil then ts=".terra" end

local ConvInner = R.FunctionGenerator("ConvInner",{"type","rate"},{},
function(args)
  local ty = args.type
  if ty:deInterface():isData()==false then
    ty = T.RV(ty:deInterface())
  end
  
  local res =  G.Function{"ConvolveInner_"..tostring(ty), ty, args.rate,
    function(inp)
      local out = G.Map{Mul}(inp)
      local res = Reduce{Add{R.Async}}(out)
      local sft = Rshift{8}(res)
      return RemoveMSBs{24}(sft)
  end}
  return res
end,
T.ParSeq(T.array2d(T.Tuple{P.DataType("L"),P.DataType("R")},P.SizeValue("V")),P.SizeValue("size")) )


local Conv = G.Function{ "Conv", SDF{1,cycles}, T.HandshakeTrigger,
  function(i)
    local ii = G.FanOut{2}(i)
    local ii0 = G.FIFO{128}(ii[0])
    local ii1 = G.FIFO{128}(ii[1])
    local res = G.AXIReadBurst{"1080p.raw",{1920,1080},u(8),noc.read}(ii0)
    local pad = Pad{{8,8,2,1}}(res)
    local trig = G.Broadcast{R.Size(Uniform(1920+8+8),1080+3)}(ii1)
    local coeffs = G.Map{RM.Storv(regs.coeffs)}(trig)
    local st = Stencil{{-3,0,-3,0}}(pad)
    st = G.Map{G.Map{AddMSBs{24}}}(st)
    local padFanIn = G.FanIn(st,coeffs)
    local padZip = G.Zip(padFanIn)
    padZip = G.Map{G.Zip}(padZip)
    res = G.Map{ConvInner}(padZip)
    res = Crop{{9,7,3,0}}(res)
    return AXIWriteBurst{"out/soc_convgenTaps_"..tostring(cycles),noc.write}(res)
  end}

harness({regs.start,Conv,regs.done},nil,{regs})
