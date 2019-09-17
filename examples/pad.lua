local R = require "rigel"
local RM = require "generators.modules"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"
local C = require "generators.examplescommon"

W = 128
H = 64


------------
inp = R.input( types.rv(types.Par(types.array2d(types.uint(8),W,H))) )
b = R.apply("b", RM.pad( types.uint(8), W,H, 2,2,2,2,0) , inp)
p100 = RM.lambda( "p100", inp, b )
------------
hsfn = RM.makeHandshake(p100)

harness{ outFile="pad", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W+4,H+4} }
