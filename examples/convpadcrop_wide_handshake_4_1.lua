local R = require "rigel"
local RS = require "rigelSimple"
local RM = require "generators.modules"
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"
local C = require "generators.examplescommon"
local J = require "common"
local soc = require "generators.soc"

--T = 8 -- throughput
function MAKE(T,ConvWidth,size1080p,NOSTALL)
  assert(type(NOSTALL)=="boolean")
  --ConvRadius = 1
  local ConvRadius = ConvWidth/2
  --local ConvWidth = ConvRadius*2
  local ConvArea = math.pow( ConvWidth, 2 )
  
  local inputW = 128
  local inputH = 64

  if size1080p then
    inputW, inputH = 1920, 1080
  end

  local fifos = {}
  local statements = {}

  local PadRadius = J.upToNearest(T, ConvRadius)
  
  -- expand to include crop region
  --W = upToNearest(T,128+ConvWidth-1)
  --H = 64+ConvWidth-1
  
  local internalW = inputW+PadRadius*2
  local internalH = inputH+ConvRadius*2
  
  --outputW = internalW
  --outputH = internalH
  
  local outputW = inputW
  local outputH = inputH
  
  local TAP_TYPE = types.array2d( types.uint(8), ConvWidth, ConvWidth )
  --soc.taps = R.newGlobal("taps","input",TAP_TYPE,J.range(ConvWidth*ConvWidth))
  local taps = soc.regStub{taps={TAP_TYPE,J.range(ConvWidth*ConvWidth)}}:instantiate("taps")
  taps.extern = true
  -------------
  -------------
  local convKernel = C.convolveTaps( types.uint(8), ConvWidth, J.sel(ConvWidth==4,7,11))
  local kernel = C.stencilKernelTaps( types.uint(8), T, TAP_TYPE, internalW, internalH, ConvWidth, ConvWidth, convKernel)
  -------------
  local BASE_TYPE = types.array2d( types.uint(8), T )
  local RW_TYPE = types.array2d( types.uint(8), 8 ) -- simulate axi bus
  --local HST = types.tuple{RW_TYPE,TAP_TYPE}
  local hsfninp_raw = R.input( R.Handshake(RW_TYPE) )
  --local inp0, inp1 = RS.fanOut{input=hsfninp_raw,branches=2}
  --local hsfninp = R.apply( "idx0", RM.makeHandshake(C.index(HST,0)), inp0 )
  --local hsfn_taps = R.apply( "idx1", RM.makeHandshake(C.index(HST,1)), inp1 )
  local out = hsfninp_raw
  
  local out = R.apply("reducerate", RM.changeRate(types.uint(8),1,8,T), out )

  local out = R.apply("pad", RM.liftHandshake(RM.padSeq(types.uint(8), inputW, inputH, T, PadRadius, PadRadius, ConvRadius, ConvRadius, 0)), out)

--  if true then
--    table.insert( fifos, R.instantiateRegistered("f_clk",RM.fifo(types.array2d(types.uint(8),T),128,false)) )
--    table.insert( statements, R.applyMethod( "s_clk", fifos[#fifos], "store", out ) )
--    out = R.applyMethod("r_clk",fifos[#fifos],"load")
--  end

  -- TAPS REGRESSION
  local out0, out1 = RS.fanOut{input=out,branches=2}
  out0 = R.apply("out0fifo",C.fifo(BASE_TYPE,128),out0)
  out1 = R.apply("out1fifo",C.fifo(BASE_TYPE,128),out1)

  local trig = R.apply("trig", RM.makeHandshake(C.valueToTrigger(BASE_TYPE),nil,true), out0)
  local tapinp = R.apply("RT", RM.makeHandshake(RM.Storv(taps.taps),nil,true), trig)
  
  local convpipeinp = R.apply("CPI", RM.packTuple({types.RV(types.Par(BASE_TYPE)),types.RV(types.Par(TAP_TYPE))}), R.concat("CONVPIPEINP",{out1,tapinp}))

  local out = R.apply("HH",RM.makeHandshake(kernel), convpipeinp)
  
  if NOSTALL then
    --table.insert( fifos, R.instantiateRegistered("f_nostall",RM.fifo(types.array2d(types.uint(8),T),2048,NOSTALL)) )
    --table.insert( statements, R.applyMethod( "s_nostall", fifos[#fifos], "store", out ) )
    --out = R.applyMethod("r_nostall",fifos[#fifos],"load")
    out = C.fifo(types.array2d(types.uint(8),T),2048,NOSTALL)(out)
  end

  local out = R.apply("crop",C.cropHelperSeq(types.uint(8), internalW, internalH, T, PadRadius+ConvRadius, PadRadius-ConvRadius, ConvRadius*2, 0), out)
  local out = R.apply("incrate", RM.changeRate(types.uint(8),1,T,8), out )

  if #fifos>0 then
    table.insert(statements,1,out)
    out = R.statements(statements)
  end

  local hsfn = RM.lambda("hsfn", hsfninp_raw, out, fifos)
  
  local infile = "frame_128.raw"
  local outfile = "convpadcrop_wide_handshake_"..ConvWidth.."_"..T

  if size1080p then 
    infile="1080p.raw" 
    outfile = outfile.."_1080p"
  end

  if NOSTALL then
    outfile = outfile.."_nostall"
  end

  harness{ outFile=outfile, fn=hsfn, inFile=infile, tapType=TAP_TYPE, tapValue=J.range(ConvWidth*ConvWidth), inSize={inputW,inputH}, outSize={outputW,outputH} }

  local sizestr = "128 "
  if size1080p then sizestr = "1080p " end

  io.output("out/"..outfile..".design.txt"); io.write("Convolution "..sizestr..ConvWidth.."x"..ConvWidth); io.close()
  io.output("out/"..outfile..".designT.txt"); io.write(T); io.close()
  io.output("out/"..outfile..".dataset.txt"); io.write("SIG16_zu9"); io.close()
end

local first = string.find(arg[0],"%d+")
local convwidth = string.sub(arg[0],first,first)
local t = string.sub(arg[0], string.find(arg[0],"%d+",first+1))

MAKE(tonumber(t),tonumber(convwidth),string.find(arg[0],"1080p"),string.find(arg[0],"nostall")~=nil)
