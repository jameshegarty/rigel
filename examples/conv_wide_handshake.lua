local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local S = require("systolic")
local harness = require("generators.harness")
local C = require "generators.examplescommon"
require "common".export()

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
inp = R.input( types.rv(types.Par(BASE_TYPE)) )

convLB = R.apply( "convLB", C.stencilLinebuffer( types.uint(8), W,H, T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), inp)
convstencils = R.apply( "convstencils", C.unpackStencil( types.uint(8), ConvWidth, ConvWidth, T ), convLB )
convpipe = R.apply( "conv",  RM.map( convolve, T ), convstencils )
convpipe = R.apply( "border", C.borderSeq( types.uint(8), inputW, inputH, T, ConvWidth-1, 0, ConvWidth-1, 0, 0 ), convpipe ) -- cut off junk

convpipe = RM.lambda( "convpipe", inp, convpipe )
-------------
hsfn = RM.makeHandshake(convpipe)

--harness.axi( "conv_wide_handshake", hsfn, "frame_128.raw", nil, nil, BASE_TYPE,T,inputW, inputH, BASE_TYPE,T, inputW, inputH )
harness{ outFile="conv_wide_handshake", fn=hsfn, inFile="frame_128.raw", inSize={inputW,inputH}, outSize={inputW,inputH} }
