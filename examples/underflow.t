local R = require "rigel"
local RM = require "modules"
local types = require("types")
local S = require("systolic")
local harness = require "harness"

W = 128
H = 64
T = 8

inp = S.parameter("inp",types.uint(8))
plus100 = RM.lift( "plus100", types.uint(8), types.uint(8) , 10, terra( a : &uint8, out : &uint8  ) @out =  @a+100 end, inp, inp + S.constant(100,types.uint(8)) )

------------
inp = R.input( types.uint(8) )
a = R.apply("a", plus100, inp)
b = R.apply("b", plus100, a)
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