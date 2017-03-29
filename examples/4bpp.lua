local R = require "rigel"
local RM = require "modules"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"

W = 128
H = 64


------------
inp = R.input( types.uint(8) )
a = R.apply("a", C.cast(types.uint(8),types.uint(4)), inp)
b = R.apply("b", C.plusConst(types.uint(4),15), a)
p100 = RM.lambda( "p100", inp, b )
------------
hsfn = RM.makeHandshake(p100)

harness{ outFile="4bpp", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H} }
