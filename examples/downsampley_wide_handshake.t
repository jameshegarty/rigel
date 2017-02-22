local RM = require "modules"
local types = require("types")
local harness = require "harness"

W = 128
H = 64
T = 8

scaleY = 4
------------
ITYPE = types.array2d( types.uint(8), T )
hsfn = RM.liftHandshake(RM.liftDecimate(RM.downsampleYSeq( types.uint(8), W,H,T,scaleY)))

harness{ outFile="downsampley_wide_handshake", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H/scaleY} }