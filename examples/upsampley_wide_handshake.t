local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"

W = 128
H = 64
T = 8

scaleY = 4
------------
ITYPE = types.array2d( types.uint(8), T )
hsfn = d.liftHandshake(d.upsampleYSeq( types.uint(8), W,H,T,scaleY))

harness.axi( "upsampley_wide_handshake", hsfn, "frame_128.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W,H*scaleY)