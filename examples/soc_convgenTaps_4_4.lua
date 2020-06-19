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

local AUTOFIFO = string.find(arg[0],"autofifo")
AUTOFIFO = (AUTOFIFO~=nil)

if AUTOFIFO then
  R.AUTO_FIFOS = true
  R.Z3_FIFOS = true
else
  R.AUTO_FIFOS = false
end

local first = string.find(arg[0],"%d+")
local ConvWidth = tonumber(string.sub(arg[0],first,first))
local V = tonumber(string.sub(arg[0], string.find(arg[0],"%d+",first+1)))

local ConvRadius = ConvWidth/2

local PadRadius = J.upToNearest(V, ConvRadius)
local cycles = ((1920+PadRadius*2)*(1080+ConvWidth))/(V/ConvWidth)
print("CYCLES",cycles)

local outfile = "soc_convgenTaps_"..tostring(ConvWidth).."_"..tostring(V)..J.sel(AUTOFIFO,"_autofifo","")
io.output("out/"..outfile..".design.txt"); io.write("Convolution 1080p "..ConvWidth.."x"..ConvWidth); io.close()
io.output("out/"..outfile..".designT.txt"); io.write(V/ConvWidth); io.close()
io.output("out/"..outfile..".dataset.txt"); io.write("SIG20_zu9"..J.sel(AUTOFIFO,"_autofifo","")); io.close()

local regs = SOC.axiRegs({
    {"coeffs",RM.reg(ar(u(8),ConvWidth,ConvWidth),J.range(ConvWidth*ConvWidth))}},SDF{1,cycles}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local ts=""
if terralib~=nil then ts=".terra" end

local ConvInner = G.SchedulableFunction{ "ConvInner", T.Array2d(T.Tuple{P.DataType("L"),P.DataType("R")},P.SizeValue("size")),
function(inp)
  print("ConvInner",inp.type)
  local out = G.Map{G.TupleToArray}(inp)
  local out = G.Map{G.Map{AddMSBs{24}}}(out)
  out = G.Map{G.ArrayToTuple}(out)
  local out = G.Map{Mul}(out)
  local res = Reduce{Add{R.Async}}(out)
  local sft = Rshift{J.sel(ConvWidth==4,7,11)}(res)
  return RemoveMSBs{sft.type:deInterface().precision-8}(sft)
end}

--local Conv = G.Function{ "Conv", SDF{1,cycles}, T.HandshakeTrigger,
local Conv = G.SchedulableFunction{ "Conv", T.Trigger,
  function(i)
    local ii = G.FanOut{2}(i)
    local ii0 = ii[0]
    ii0 = G.NAUTOFIFO{128}(ii0)
    local ii1 = ii[1]
    ii1 = G.NAUTOFIFO{128}(ii1)
    
    local res = G.AXIReadBurst{"1080p.raw",{1920,1080},u(8),noc.read}(ii0)

    --local T = Uniform(res.type:deInterface().V[1]*res.type:deInterface().V[2]):toNumber()
    --local PadRadius = J.upToNearest(T, ConvRadius)

    local pad = Pad{{PadRadius, PadRadius, ConvRadius, ConvRadius}}(res)
    print("PAD",pad.type,pad.rate)
    local st = Stencil{{-ConvWidth+1,0,-ConvWidth+1,0}}(pad)
    print("ST",st.type,st.rate)
    --st = G.Map{G.Map{AddMSBs{24}}}(st)
    -----
    local trig = G.Broadcast{R.Size(Uniform(1920+PadRadius*2),1080+ConvRadius*2)}(ii1)
    local coeffs = G.Map{RM.Storv(regs.coeffs)}(trig)
    print("TOCOL",coeffs.type,coeffs.rate)
    coeffs = G.Map{G.ToColumns}(coeffs)
    -----
    print("STCOEFFS",st.type,coeffs.type)
    local padFanIn = G.FanIn(st,coeffs)
    local padZip = G.Zip(padFanIn)
    print("PadSip",padZip.type,padZip.rate)
    padZip = G.Map{G.Zip}(padZip)
    res = G.Map{ConvInner}(padZip)
    res = Crop{{PadRadius+ConvRadius, PadRadius-ConvRadius, ConvRadius*2, 0}}(res)
    return AXIWriteBurst{"out/"..outfile,noc.write}(res)
  end}

harness({regs.start,Conv,regs.done},nil,{regs})
