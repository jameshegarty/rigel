local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"

T = 1 -- throughput

--ConvRadius = 1
local ConvRadius = 2
local ConvWidth = ConvRadius*2+1
local ConvArea = math.pow( ConvWidth, 2 )

local inputW = 128
local inputH = 64

--local PadRadius = upToNearest(T, ConvRadius)

-- expand to include crop region
--W = upToNearest(T,128+ConvWidth-1)
--H = 64+ConvWidth-1

--local internalW = inputW+PadRadius*2
--local internalH = inputH+ConvRadius*2

--outputW = internalW
--outputH = internalH

local outputW = inputW
local outputH = inputH

function conv(internalW, internalH)
  print("CONV",internalW,internalH)
  local convolve = C.convolveConstant( types.uint(8), ConvWidth, rep(1,ConvWidth*ConvWidth), 5 )
  local convpipe = C.stencilKernel( types.uint(8), T, internalW, internalH, ConvWidth, ConvWidth, convolve )
  return d.makeHandshake(convpipe)
end

hsfn = C.padcrop(types.uint(8),inputW,inputH,T,ConvRadius,ConvRadius,ConvRadius,ConvRadius,0,conv)
-------------

local RW_TYPE = types.array2d( types.uint(8), T ) -- simulate axi bus
harness.sim( "convpadcrop_handshake", hsfn, "frame_128.raw", nil, nil,  RW_TYPE, T, inputW, inputH, RW_TYPE, T, outputW, outputH )
