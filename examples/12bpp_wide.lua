local R = require "rigel"
local RM = require "modules"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"

W = 128
H = 64
T = 8

------------
inp = R.input( types.uint(8) )
a = R.apply("a", C.cast(types.uint(8),types.uint(12)), inp)
b = R.apply("b", C.plus100(types.uint(12)), a)
p100 = RM.lambda( "p100", inp, b )
------------
ITYPE = types.array2d( types.uint(8), T )
inp = R.input( ITYPE )
out = R.apply( "plus100", RM.map( p100, T ), inp )
fn = RM.lambda( "pointwise_wide", inp, out )
------------
hsfn = RM.makeHandshake(fn)

harness{ outFile="12bpp_wide", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H} }
