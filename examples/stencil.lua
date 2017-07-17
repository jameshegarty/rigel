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
b = R.apply("a", C.stencil( types.uint(8), W,H, -1,1,-1,1) , inp)
b = R.apply("b", RM.map(C.index(types.array2d(types.uint(8),3,3),2,2),W,H), b)
b = R.apply("c", RM.crop( types.uint(8), W,H, 1,1,1,1) , b)
p100 = RM.lambda( "p100", inp, b )
------------
hsfn = RM.makeHandshake(p100)

harness{ outFile="stencil", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W-2,H-2} }
