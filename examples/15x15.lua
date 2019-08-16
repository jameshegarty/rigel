local R = require "rigel"
local RM = require "generators.modules"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"
local C = require "generators.examplescommon"
require "common".export()

W = 15
H = 15
T = 1


------------
inp = R.input( types.rv(types.Par(types.uint(8))) )
a = R.apply("a", C.plus100(types.uint(8)), inp)
b = R.apply("b", C.plus100(types.uint(8)), a)
p200 = RM.lambda( "p200", inp, b )
------------
hsfn = RM.makeHandshake(p200)

harness{ outFile="15x15", fn=hsfn, inFile="15x15.raw", inSize={W,H}, outSize={W,H} }
