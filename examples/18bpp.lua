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
inp = R.input( types.rv(types.Par(types.uint(8))) )
a = R.apply("a", C.cast(types.uint(8),types.uint(18)), inp)
b = R.apply("b", C.plusConst(types.uint(18),69926), a)
p100 = RM.lambda( "p100", inp, b )
------------
hsfn = RM.makeHandshake(p100)

harness{ outFile="18bpp", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H} }
