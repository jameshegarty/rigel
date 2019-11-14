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

local regs = SOC.axiRegs({
  {"coeffs",RM.reg(ar(u(32),ConvWidth,ConvWidth),
          {4, 14, 14,  4,
           14, 32, 32, 14,
           14, 32, 32, 14,
           4, 14, 14,  4})}},SDF{1,cycles}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

--print("coeffs",regs.coeffs)
  
local ConvInner = R.FunctionGenerator("ConvInner",{"type","rate"},{},
function(args)
--  print("MAKE CONF INNER",args.type)
  local res =  G.Module{"ConvolveInner_"..tostring(args.type), args.type, args.rate,
    function(inp)
      local i0 = inp[0]
      local i1 = inp[1]
      local px = AddMSBs{24}(i0)
      local coeffs = G.Map{RM.Storv(regs.coeffs)}(i1)
      local z = Zip(px,coeffs)
      --print("ZIP1OUT",z.type)
      z = Zip(z)
      --print("ZIP2OUT",z.type)
      local out = Mul(z)
      --print("MULOUT",out.type)
      local res = Reduce{Add{R.Async}}(out)
      return RemoveMSBs{24}(Rshift{8}(res))
  end}
--  print("CONVINNER",res)
  return res
end,
P.SumType("opt",{
  T.rv( T.ParSeq(T.array2d(T.Tuple{P.DataType("T"),T.Trigger},P.SizeValue("V")),P.SizeValue("size"))),
  T.rv( T.Tuple{T.Seq(T.Par(P.DataType("T")),P.SizeValue("size")),T.Seq(T.Par(T.Trigger),P.SizeValue("size"))} ),
  T.rv( T.Tuple{T.Par(T.array2d(P.DataType("T"),P.SizeValue("size"))),T.Par(T.array2d(T.Trigger,P.SizeValue("size")))} )
}),
P.SumType("opt",{
  T.rv(T.Par(P.DataType("T"))),
  T.rv(T.Par(P.DataType("T"))),
  T.rv(T.Par(P.DataType("T")))}) )


local Conv = G.Module{"Conv",SDF{1,cycles},
  function(i)
    --print("CONVINP",i.type)
    local ii = G.FanOut{2}(i)
    local ii0 = G.FIFO{128}(ii[0])
    local ii1 = G.FIFO{128}(ii[1])
    local res = G.AXIReadBurst{"1080p.raw",{1920,1080},u(8),noc.read}(ii0)
    print("READ",res.type)
    local pad = Pad{{8,8,2,1}}(res)
    print("PAD",pad.type)
    --local padFan = G.FanOut{2}(pad)
    --local padlhs = G.FIFO{128}(padFan[0])
    --local padTrig = G.ValueToTrigger(padFan[1])
    --padTrig = G.FIFO{128}(padTrig)
    local trig = G.Broadcast{R.Size(Uniform(1920+8+8),1080+2+1)}(ii1)

    print("TRIG",trig.type)
    --print("PADTRIG",pad.type,trig.type)
    
    res = Stencil{{-3,0,-3,0}}(pad)
    print("ST",res.type)
    --print(padTrig)
    --print("PADD",pad.type,padTrig.type)
    local padFanIn = G.FanIn(res,trig)
    --print("PadFanIn",padFanIn)
    local padZip = G.Zip(padFanIn)
    print("ZIP",padZip.type)
    res = ConvInner(padZip)
    print("CONV",res.type)
    res = Crop{{9,7,3,0}}(res)
    print("CRP",res.type)
    return AXIWriteBurst{"out/soc_convgenTaps_"..tostring(cycles),noc.write}(res)
  end}

harness({regs.start,Conv,regs.done},nil,{regs})
