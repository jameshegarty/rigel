local R = require "rigel"
local RM = require "modules"
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"

--T = 8 -- throughput
function MAKE(T,ConvWidth,size1080p)
  assert(T<=1)
  --ConvRadius = 1
  local ConvRadius = ConvWidth/2
  -- put center at (ConvRadius,ConvRadius)
  --local ConvWidth = ConvRadius*2
  local ConvArea = math.pow( ConvWidth, 2 )
  
  local inputW = 128
  local inputH = 64

  if size1080p then
    print("1080p")
    inputW, inputH = 1920, 1080
  end
  
  local PadRadius = upToNearest(T, ConvRadius)
  
  -- expand to include crop region
  --W = upToNearest(T,128+ConvWidth-1)
  --H = 64+ConvWidth-1
  
  local internalW = inputW+PadRadius*2
  local internalH = inputH+ConvRadius*2
  
  --outputW = internalW
  --outputH = internalH
  
  local outputW = inputW
  local outputH = inputH
  
  local convolve = C.convolveConstantTR( types.uint(8), ConvWidth, ConvWidth, T, range(ConvWidth*ConvWidth), sel(ConvWidth==4,7,11) )
  -------------
  local RW_TYPE = types.array2d( types.uint(8), 8 ) -- simulate axi bus
  local hsfninp = R.input( R.Handshake(RW_TYPE) )

  local out = R.apply("reducerate", RM.liftHandshake(RM.changeRate(types.uint(8),1,8,1)), hsfninp )
  local out = R.apply("pad", RM.liftHandshake(RM.padSeq(types.uint(8), inputW, inputH, 1, PadRadius, PadRadius, ConvRadius, ConvRadius, 0)), out)

  local out = R.apply( "convLB", C.stencilLinebufferPartial( types.uint(8), internalW, internalH, T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), out)
  local out = R.apply( "conv", RM.liftHandshake(convolve), out )
  
  local out = R.apply("crop",RM.liftHandshake(RM.liftDecimate(C.cropHelperSeq(types.uint(8), internalW, internalH, 1, PadRadius+ConvRadius, PadRadius-ConvRadius, ConvRadius*2, 0))), out)
  local out = R.apply("incrate", RM.liftHandshake(RM.changeRate(types.uint(8),1,1,8)), out )
  local hsfn = RM.lambda("hsfn", hsfninp, out)
  
  local infile = "frame_128.raw"
  local outfile = "conv_tr_handshake_"..tostring(ConvWidth).."_"..(1/T)

  if size1080p then 
    infile="1080p.raw" 
    outfile = outfile.."_1080p"
  end

  harness{ outFile=outfile, fn=hsfn, inFile=infile, inSize={inputW,inputH}, outSize={outputW,outputH} }

  local sizestr = "128 "
  if size1080p then sizestr = "1080p " end

  io.output("out/"..outfile..".design.txt"); io.write("Convolution "..sizestr..ConvWidth.."x"..ConvWidth); io.close()
  io.output("out/"..outfile..".designT.txt"); io.write(T); io.close()
end

local first = string.find(arg[0],"%d+")
local convwidth = string.sub(arg[0],first,first)
local t = string.sub(arg[0], string.find(arg[0],"%d+",first+1))
print("ConvWidth",convwidth,"T",t)

MAKE(1/tonumber(t),tonumber(convwidth),string.find(arg[0],"1080p"))
