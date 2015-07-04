local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require "harness"

T = 8 -- throughput
--ConvRadius = 1
ConvWidth = 4
ConvArea = math.pow(ConvWidth,2)

inputW = 128
inputH = 64

-- expand to include crop region
W = upToNearest(T,128+ConvWidth-1)
H = 64+ConvWidth-1


BASE_TYPE = types.array2d( types.uint(8), T )

hsfn = d.compose("HSFN",
                 d.liftHandshake(d.liftDecimate(d.cropSeq(types.uint(8), W, H, T, 0, (W-inputW), 0, (H-inputH), 0))),
                 d.liftHandshake(d.padSeq(types.uint(8), inputW, inputH, T, (W-inputW), 0, (H-inputH), 0, 128)) )

harness.axi( "padcrop_wide_handshake", hsfn, BASE_TYPE, inputW, inputH, BASE_TYPE, inputW, inputH )
