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
local J = require "common"

R.Z3_FIFOS = true

local first = string.find(arg[0],"%d+")
local ConvWidth = tonumber(string.sub(arg[0],first,first))
local V = tonumber(string.sub(arg[0], string.find(arg[0],"%d+",first+1)))

local ConvRadius = ConvWidth/2


local PadRadius = J.upToNearest(V, ConvRadius)
local cycles = ((1920+PadRadius*2)*(1080+ConvWidth))/(V/ConvWidth)
print("CYCLES",cycles)

local regs = SOC.axiRegs({
    {"coeffs",RM.reg(ar(u(32),ConvWidth,ConvWidth),J.range(ConvWidth*ConvWidth))}},SDF{1,cycles}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local ts=""
if terralib~=nil then ts=".terra" end

local ConvInner = G.SchedulableFunction{ "ConvInner", T.Array2d(T.Tuple{P.DataType("L"),P.DataType("R")},P.SizeValue("size")),
function(inp)
  local out = G.Map{Mul}(inp)
  local res = Reduce{Add{R.Async}}(out)
  local sft = Rshift{J.sel(ConvWidth==4,7,11)}(res)
  return RemoveMSBs{24}(sft)
end}

--local Conv = G.Function{ "Conv", SDF{1,cycles}, T.HandshakeTrigger,
local Conv = G.SchedulableFunction{ "Conv", T.Trigger,
  function(i)
    local ii = G.FanOut{2}(i)
    local ii0 = ii[0]
    local ii1 = ii[1]
    
    local res = G.AXIReadBurst{"1080p.raw",{1920,1080},u(8),noc.read}(ii0)

    local T = Uniform(res.type:deInterface().V[1]*res.type:deInterface().V[2]):toNumber()
    local PadRadius = J.upToNearest(T, ConvRadius)

    local pad = Pad{{PadRadius, PadRadius, ConvRadius, ConvRadius}}(res)
    local st = Stencil{{-ConvWidth+1,0,-ConvWidth+1,0}}(pad)
    st = G.Map{G.Map{AddMSBs{24}}}(st)
    -----
    local trig = G.Broadcast{R.Size(Uniform(1920+PadRadius*2),1080+ConvRadius*2)}(ii1)
    local coeffs = G.Map{RM.Storv(regs.coeffs)}(trig)
    -----
    local padFanIn = G.FanIn(st,coeffs)
    local padZip = G.Zip(padFanIn)
    padZip = G.Map{G.Zip}(padZip)
    res = G.Map{ConvInner}(padZip)
    res = Crop{{PadRadius+ConvRadius, PadRadius-ConvRadius, ConvRadius*2, 0}}(res)
    return AXIWriteBurst{"out/soc_convgenTaps_"..tostring(ConvWidth).."_"..tostring(V),noc.write}(res)
  end}

harness({regs.start,Conv,regs.done},nil,{regs})
