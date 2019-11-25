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
  local res =  G.Module{"ConvolveInner_"..tostring(args.type), args.type, args.rate,
    function(inp)
      local out = Mul(inp)
      local res = Reduce{Add{R.Async}}(out)
      local sft = Rshift{8}(res)
      return RemoveMSBs{24}(sft)
  end}
  return res
end,
P.SumType("opt",{
  T.RV( T.ParSeq(T.array2d(T.Tuple{P.DataType("L"),P.DataType("R")},P.SizeValue("V")),P.SizeValue("size"))),
  T.RV( T.Seq(T.Par(T.Tuple{P.DataType("L"),P.DataType("R")}),P.SizeValue("size")) ),
  T.rv( T.Par(T.array2d(T.Tuple{P.DataType("L"),P.DataType("R")},P.SizeValue("size"))))
}),
P.SumType("opt",{
  T.RV(P.ScheduleType("S")),
  T.RV(P.ScheduleType("S")),
  T.rv( T.Par(P.DataType("D")) )}) )


local Conv = G.Module{"Conv",SDF{1,cycles},T.HandshakeTrigger,
  function(i)
    local ii = G.FanOut{2}(i)
    local ii0 = G.FIFO{128}(ii[0])
    local ii1 = G.FIFO{128}(ii[1])
    local res = G.AXIReadBurst{"1080p.raw",{1920,1080},u(8),noc.read}(ii0)
    local pad = Pad{{8,8,2,1}}(res)
    local trig = G.Broadcast{R.Size(Uniform(1920+8+8),1080+3)}(ii1)
    local coeffs = G.Map{RM.Storv(regs.coeffs)}(trig)
    coeffs = G.Reshape(coeffs)
    coeffs = G.Reshape(coeffs)
    local st = Stencil{{-3,0,-3,0}}(pad)
    st = G.Reshape(st)
    st = G.Reshape(st)
    st = AddMSBs{24}(st)
    local padFanIn = G.FanIn(st,coeffs)
    local padZip = G.Zip(padFanIn)
    padZip = G.Zip(padZip)
    res = ConvInner(padZip)
    res = Crop{{9,7,3,0}}(res)
    return AXIWriteBurst{"out/soc_convgenTaps_"..tostring(cycles),noc.write}(res)
  end}

harness({regs.start,Conv,regs.done},nil,{regs})
