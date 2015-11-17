local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"

--T = 8 -- throughput
function MAKE(T,ConvWidth)
  assert(T<=1)
--ConvRadius = 1
local ConvRadius = ConvWidth/2
-- put center at (ConvRadius,ConvRadius)
--local ConvWidth = ConvRadius*2
local ConvArea = math.pow( ConvWidth, 2 )

local inputW = 128
local inputH = 64

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
local hsfninp = d.input( d.Handshake(RW_TYPE) )
--local out = hsfninp
local out = d.apply("reducerate", d.liftHandshake(d.changeRate(types.uint(8),1,8,1)), hsfninp )
local out = d.apply("pad", d.liftHandshake(d.padSeq(types.uint(8), inputW, inputH, 1, PadRadius, PadRadius, ConvRadius, ConvRadius, 0)), out)
--local out = d.apply("HH",d.liftHandshake(convpipe), out)
local out = d.apply( "convLB", d.stencilLinebufferPartial( types.uint(8), internalW, internalH, T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), out)
local out = d.apply( "conv", d.liftHandshake(convolve), out )

local out = d.apply("crop",d.liftHandshake(d.liftDecimate(d.cropHelperSeq(types.uint(8), internalW, internalH, 1, PadRadius+ConvRadius, PadRadius-ConvRadius, ConvRadius*2, 0))), out)
local out = d.apply("incrate", d.liftHandshake(d.changeRate(types.uint(8),1,1,8)), out )
local hsfn = d.lambda("hsfn", hsfninp, out)

harness.axi( "conv_tr_handshake_"..tostring(ConvWidth).."_"..(1/T), hsfn, "frame_128.raw", nil, nil, RW_TYPE, 8,inputW, inputH, RW_TYPE, 8,outputW, outputH )
end

local first = string.find(arg[0],"%d+")
local convwidth = string.sub(arg[0],first,first)
local t = string.sub(arg[0], string.find(arg[0],"%d+",first+1))
print("ConvWidth",convwidth,"T",t)

MAKE(1/tonumber(t),tonumber(convwidth))
