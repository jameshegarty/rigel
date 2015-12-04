local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"

--T = 8 -- throughput
function MAKE(T,ConvWidth,size1080p)
  --ConvRadius = 1
  local ConvRadius = ConvWidth/2
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
  
  local TAP_TYPE = types.array2d( types.uint(8), ConvWidth, ConvWidth ):makeConst()
  -------------
  -------------
  local convKernel = C.convolveTaps( types.uint(8), ConvWidth, sel(ConvWidth==4,7,11))
  local kernel = C.stencilKernelTaps( types.uint(8), T, TAP_TYPE, internalW, internalH, ConvWidth, ConvWidth, convKernel)
  -------------
  local BASE_TYPE = types.array2d( types.uint(8), T )
  local RW_TYPE = types.array2d( types.uint(8), 8 ) -- simulate axi bus
  local HST = types.tuple{RW_TYPE,TAP_TYPE}
  local hsfninp_raw = d.input( d.Handshake(HST) )
  local hsfninp = d.apply( "idx0", d.makeHandshake(d.index(HST,0)), hsfninp_raw )
  local hsfn_taps = d.apply( "idx1", d.makeHandshake(d.index(HST,1)), hsfninp_raw )
  local out = hsfninp
  
  local out = d.apply("reducerate", d.liftHandshake(d.changeRate(types.uint(8),1,8,T)), out )
  --local out = d.apply("FW",d.makeHandshake(d.fwriteSeq("KERNOUT.raw",types.array2d(types.uint(8),T))), out)
  local out = d.apply("pad", d.liftHandshake(d.padSeq(types.uint(8), inputW, inputH, T, PadRadius, PadRadius, ConvRadius, ConvRadius, 0)), out)
  
  local convpipeinp = d.apply("CPI", darkroom.packTuple({BASE_TYPE,TAP_TYPE}), d.tuple("CONVPIPEINP",{out,hsfn_taps},false))
  local out = d.apply("HH",d.makeHandshake(kernel), convpipeinp)
  local out = d.apply("crop",d.liftHandshake(d.liftDecimate(d.cropHelperSeq(types.uint(8), internalW, internalH, T, PadRadius+ConvRadius, PadRadius-ConvRadius, ConvRadius*2, 0))), out)
  local out = d.apply("incrate", d.liftHandshake(d.changeRate(types.uint(8),1,T,8)), out )
  local hsfn = d.lambda("hsfn", hsfninp_raw, out)
  
  local infile = "frame_128.raw"
  local outfile = "convpadcrop_wide_handshake_"..ConvWidth.."_"..T

  if size1080p then 
    infile="1080p.raw" 
    outfile = outfile.."_1080p"
  end

  harness.axi( outfile, hsfn, infile, TAP_TYPE, range(ConvWidth*ConvWidth), RW_TYPE, 8, inputW, inputH, RW_TYPE, 8, outputW, outputH )

  local sizestr = "128 "
  if size1080p then sizestr = "1080p " end

  io.output("out/"..outfile..".design.txt"); io.write("Convolution "..sizestr..ConvWidth.."x"..ConvWidth); io.close()
  io.output("out/"..outfile..".designT.txt"); io.write(T); io.close()

  --harness.axi( "convpadcrop_wide_handshake_"..T, hsfn, RW_TYPE, inputW, inputH, types.array2d( types.uint(8), 4 ), outputW, outputH )
end

local first = string.find(arg[0],"%d+")
local convwidth = string.sub(arg[0],first,first)
local t = string.sub(arg[0], string.find(arg[0],"%d+",first+1))
print("ConvWidth",convwidth,"T",t)

MAKE(tonumber(t),tonumber(convwidth),string.find(arg[0],"1080p"))
