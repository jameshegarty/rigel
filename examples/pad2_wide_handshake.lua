local RM = require "modules"
local C = require "examplescommon"
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
W = inputW+16
H = inputH+2

WW = W+16
HH = H+2

BASE_TYPE = types.array2d( types.uint(8), T )

hsfn = C.compose("HSFN",
                 RM.liftHandshake(RM.padSeq(types.uint(8), W, H, T, (WW-W), 0, (HH-H), 0, 128)),
                 RM.liftHandshake(RM.padSeq(types.uint(8), inputW, inputH, T, (W-inputW), 0, (H-inputH), 0, 0)) )

harness{ outFile="pad2_wide_handshake", fn=hsfn, inFile="frame_128.raw", inSize={inputW,inputH}, outSize={WW,HH} }