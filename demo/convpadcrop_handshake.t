local RM = require "modules"
local types = require("types")
local harness = require "harness"
local C = require "examplescommon"

T = 1 -- throughput

--ConvRadius = 1
local ConvRadius = 2
local ConvWidth = ConvRadius*2+1
local ConvArea = math.pow( ConvWidth, 2 )

local inputW = 128
local inputH = 64

local outputW = inputW
local outputH = inputH

function conv(internalW, internalH)
  print("CONV",internalW,internalH)
  local convolve = C.convolveConstant( types.uint(8), ConvWidth, ConvWidth, rep(1,ConvWidth*ConvWidth), 5 )
  local convpipe = C.stencilKernel( types.uint(8), T, internalW, internalH, ConvWidth, ConvWidth, convolve )
  return RM.makeHandshake(convpipe)
end

hsfn = C.padcrop(types.uint(8),inputW,inputH,T,ConvRadius,ConvRadius,ConvRadius,ConvRadius,0,conv)
-------------

-- b/c of padcrop FIFO in _half test.
EARLY_OVERRIDE = 1200
local RW_TYPE = types.array2d( types.uint(8), T ) -- simulate axi bus
harness.sim( "convpadcrop_handshake", hsfn, "frame_128.raw", nil, nil,  RW_TYPE, T, inputW, inputH, RW_TYPE, T, outputW, outputH,nil,EARLY_OVERRIDE )
