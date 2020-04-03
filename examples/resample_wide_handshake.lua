local RM = require "generators.modules"
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"
local C = require "generators.examplescommon"
local J = require "common"

T = 8 -- throughput

local ConvWidth = 8

local inputW = 128
local inputH = 64

local outputW = inputW
local outputH = inputH

function conv(internalW, internalH)
  print("CONV",internalW,internalH)
  local convolve = C.convolveConstant( types.uint(8), ConvWidth, ConvWidth, J.broadcast(1,ConvWidth*ConvWidth), 6 )
  local convpipe = C.stencilKernel( types.uint(8), T, internalW, internalH, ConvWidth, ConvWidth, convolve )
  return RM.makeHandshake(convpipe)
end

hsfn = C.padcrop( types.uint(8), inputW, inputH, T, 4, 3, 4, 3, 0, conv )
local scale = 2
local downsample = C.downsampleSeq( types.uint(8), inputW, inputH, T, scale, scale)
hsfn = C.compose( "rhsfn", downsample, hsfn )
-------------

local RW_TYPE = types.array2d( types.uint(8), T ) -- simulate axi bus
--harness.axi( "resample_wide_handshake", hsfn, "frame_128.raw", nil, nil, RW_TYPE, T,inputW, inputH, RW_TYPE, T,outputW/scale, outputH/scale )
harness{ outFile = "resample_wide_handshake", fn=hsfn, inFile="frame_128.raw", inSize={inputW,inputH}, outSize={outputW/scale, outputH/scale} }
