local R = require "rigel"
local RM = require "modules"
local types = require("types")
local harness = require "harness"
local fixed = require "fixed"

W = 128
H = 64
T = 8

------------
local ainp = fixed.parameter("ainp",types.uint(8))
local a = (ainp:lift(0)*fixed.constant(64,false,9,0)):hist("a"):normalize(8):hist("a_norm"):toDarkroom("a")
------------
local binp = fixed.parameter("ainp",fixed.type(false,8,9))
-- The compiler doesn't know if the 9 bit thing is 2^9=512 or 64. So when we squish it into 8 bits, we lose precision
local b = (binp*fixed.constant(64,false,8,0)):hist("b"):normalize(8):rshift(12):denormalize():truncate(8):hist("b_atend"):lower():toDarkroom("b")
------------
ITYPE = types.array2d( types.uint(8), T )
inp = R.input( ITYPE )
out = R.apply( "a", RM.map( a, T ), inp )
out = R.apply( "b", RM.map( b, T ), out )
fn = RM.lambda( "fixed_wide", inp, out )
------------
hsfn = RM.makeHandshake(fn)

harness.axi( "fixed_wide_handshake", hsfn, "frame_128.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W,H)

fixed.printHistograms()