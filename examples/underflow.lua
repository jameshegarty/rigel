local R = require "rigel"
local RM = require "modules"
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"

W = 128
H = 64
T = 8




------------
inp = R.input( types.uint(8) )
a = R.apply("a", C.plus100, inp)
b = R.apply("b", C.plus100, a)
p200 = RM.lambda( "p200", inp, b )
------------
ITYPE = types.array2d( types.uint(8), T )
inp = R.input( ITYPE )
out = R.apply( "plus100", RM.map( p200, T ), inp )
fn = RM.lambda( "pointwise_wide", inp, out )
------------
hsfn = RM.makeHandshake(fn)

--harness.axi( "underflow", hsfn, "frame_128.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W,H, true)
harness{ outFile="underflow", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H}, underflowTest=true}