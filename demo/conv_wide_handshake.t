local R = require "rigel"
local RM = require "modules"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require("harness")
local C = require "examplescommon"

T = 8 -- throughput
--ConvRadius = 1
ConvWidth = 4
ConvArea = math.pow(ConvWidth,2)

inputW = 128
inputH = 64

-- expand to include crop region
--W = upToNearest(T,128+ConvWidth-1)
--H = 64+ConvWidth-1

W = inputW
H = inputH

local convolve = C.convolveConstant( types.uint(8), ConvWidth, ConvWidth, range(ConvArea), 8 )
-------------
BASE_TYPE = types.array2d( types.uint(8), T )
inp = R.input( BASE_TYPE )

convLB = R.apply( "convLB", C.stencilLinebuffer( types.uint(8), W,H, T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), inp)
convstencils = R.apply( "convstencils", C.unpackStencil( types.uint(8), ConvWidth, ConvWidth, T ), convLB )
convpipe = R.apply( "conv",  RM.map( convolve, T ), convstencils )
convpipe = R.apply( "border", C.borderSeq( types.uint(8), inputW, inputH, T, ConvWidth-1, 0, ConvWidth-1, 0, 0 ), convpipe ) -- cut off junk

convpipe = RM.lambda( "convpipe", inp, convpipe )
-------------
hsfn = RM.makeHandshake(convpipe)

harness.axi( "conv_wide_handshake", hsfn, "frame_128.raw", nil, nil, BASE_TYPE,T,inputW, inputH, BASE_TYPE,T, inputW, inputH )