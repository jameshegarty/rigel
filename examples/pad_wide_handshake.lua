local RM = require "modules"
local types = require("types")
local S = require("systolic")
local harness = require "harness"

T = 8 -- throughput
--ConvRadius = 1
ConvWidth = 4
ConvArea = math.pow(ConvWidth,2)

inputW = 128
inputH = 64

-- must be aligned to axi burst size
W = inputW+32
H = inputH+4

BASE_TYPE = types.array2d( types.uint(8), T )

hsfn = RM.liftHandshake(RM.padSeq(types.uint(8), inputW, inputH, T, (W-inputW), 0, (H-inputH), 0, 0))

harness{ outFile="pad_wide_handshake",fn=hsfn, inFile="frame_128.raw", inSize={inputW,inputH}, outSize={W,H}}
