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
inp = R.input( types.array2d(types.uint(8),W,H) )
b = R.apply("b", RM.pad( types.uint(8), W,H, 2,2,2,2,0) , inp)
p100 = RM.lambda( "p100", inp, b )
------------
hsfn = RM.makeHandshake(p100)

harness{ outFile="pad", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W+4,H+4} }
