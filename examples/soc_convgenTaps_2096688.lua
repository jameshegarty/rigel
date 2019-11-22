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

--print("coeffs",regs.coeffs)

local ts=""
if terralib~=nil then ts=".terra" end

local ConvInner = R.FunctionGenerator("ConvInner",{"type","rate"},{},
function(args)
--  print("MAKE CONF INNER",args.type)
  local res =  G.Module{"ConvolveInner_"..tostring(args.type), args.type, args.rate,
    function(inp)
--      local i0 = inp[0]
--      local i1 = inp[1]
--      local px = AddMSBs{24}(i0)
      --local coeffs = G.Map{RM.Storv(regs.coeffs)}(i1)
      --local z = Zip(px,coeffs)
      --print("ZIP1OUT",z.type)
      --z = Zip(z)
      --print("ZIP2OUT",z.type)
      local out = Mul(inp)
--      out = G.FwriteArray{"out/mul"..ts..".data"}(out)
      
      --print("MULOUT",out.type)
      local res = Reduce{Add{R.Async}}(out)
      local sft = Rshift{8}(res)
--      sft = G.Fwrite{"out/sft"..ts..".data"}(sft)
      return RemoveMSBs{24}(sft)
--      return RemoveMSBs{24}(res)
  end}
--  print("CONVINNER",res)
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
    --print("CONVINP",i.type)
    local ii = G.FanOut{2}(i)
    local ii0 = G.FIFO{128}(ii[0])
    local ii1 = G.FIFO{128}(ii[1])
    local res = G.AXIReadBurst{"1080p.raw",{1920,1080},u(8),noc.read}(ii0)
    --print("READ",res.type)
    local pad = Pad{{8,8,2,1}}(res)
    --pad = G.FwriteArray{"out/pad.data"}(pad)
    
    print("PAD",pad.type,pad.rate)
    --local padFan = G.FanOut{2}(pad)
    --local padlhs = G.FIFO{128}(padFan[0])
    --local padTrig = G.ValueToTrigger(padFan[1])
    --padTrig = G.FIFO{128}(padTrig)
    local trig = G.Broadcast{R.Size(Uniform(1920+8+8),1080+3)}(ii1)

    --print("TRIG",trig.type)
    
    local coeffs = G.Map{RM.Storv(regs.coeffs)}(trig)

    --print("coeff",coeffs.type,coeffs.rate)
    coeffs = G.Reshape(coeffs)
    --print("coeff2",coeffs.type)
    coeffs = G.Reshape(coeffs)
    
    coeffs = G.FwriteArray{"out/coeffs"..ts..".data"}(coeffs)
    --print("coeff3",coeffs.type)
    
    --print("PADTRIG",pad.type,trig.type)
    
    local st = Stencil{{-3,0,-3,0}}(pad)
    --st = Crop{{9,7,3,0}}(st)
    
    --print("ST",st.type)
    st = G.Reshape(st)
    --print("ST",st.type)
    st = G.Reshape(st)
    print("ST",st.type,st.rate)

    --st = G.FwriteArray{"out/st"..ts..".data"}(st)
    
    st = AddMSBs{24}(st)

    --st = G.FwriteArray{"out/msb"..ts..".data"}(st)
    --print(padTrig)
    --print("PADD",pad.type,padTrig.type)
    local padFanIn = G.FanIn(st,coeffs)

    --print("PadFanIn",padFanIn.type)
    local padZip = G.Zip(padFanIn)
    print("ZIP",padZip.type,padZip.rate,padZip.fn)
    --padZip = G.Fwrite{"out/padZip0"..ts..".data"}(padZip)
    
    padZip = G.Zip(padZip)
    print("ZIP2",padZip.type,padZip.rate,padZip.fn)

    --padZip = G.FwriteArray{"out/padZip"..ts..".data"}(padZip)

    print("PADZIP",padZip.type,padZip.rate)
    res = ConvInner(padZip)

    print("ReS",res.type,res.rate)
    --print(res.fn)

    --res = G.Fwrite{"out/conv.data"}(res)
    --print(res.fn)
    --print(res.terraModule.meth)
    --res.fn.terraModule.methods.process:printpretty(false)
    --print("CONV",res.type)

    res = Crop{{9,7,3,0}}(res)
    --print("CRP",res.type)
    return AXIWriteBurst{"out/soc_convgenTaps_"..tostring(cycles),noc.write}(res)
  end}

--print("CONV",Conv)

harness({regs.start,Conv,regs.done},nil,{regs})
