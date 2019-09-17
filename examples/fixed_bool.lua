local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local harness = require "generators.harness"
local f = require "fixed"

W = 128
H = 64
T = 8

------------
local ainp = f.parameter("ainp",types.uint(8))
local a = ainp:lift(0)
local lowband = ( a:lt(f.constant(32)) ):__and( a:gt(f.constant(16)) )
local highband = ( a:le(f.constant(220)) ):__and( a:ge(f.constant(200)) )
local aout = f.select( (lowband:__or(highband)):__not(), f.plainconstant(200,types.uint(8)), f.plainconstant(32,types.uint(8)) ):disablePipelining()
local amod = aout:toRigelModule("a")
------------
ITYPE = types.array2d( types.uint(8), T )
inp = R.input( types.rv(types.Par(ITYPE)) )
out = R.apply( "a", RM.map( amod, T ), inp )
fn = RM.lambda( "fixed_wide", inp, out )
------------
hsfn = RM.makeHandshake(fn)

--harness.axi( "fixed_wide_handshake", hsfn, "frame_128.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W,H)
harness{ outFile="fixed_bool", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H} }

--fixed.printHistograms()
