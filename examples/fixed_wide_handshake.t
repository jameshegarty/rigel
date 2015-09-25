local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"
local fixed = require "fixed"

W = 128
H = 64
T = 8

------------
local ainp = fixed.parameter("ainp",types.uint(8))
local a = (ainp:lift(0)*fixed.constant(64,false,9,0)):hist("a"):normalize(11):hist("a_norm"):toDarkroom("a")
------------
local binp = fixed.parameter("ainp",fixed.type(false,11,8))
-- The compiler doesn't know if the 9 bit thing is 2^9=512 or 64. So when we squish it into 8 bits, we lose precision
local b = (binp*fixed.constant(64,false,8,0)):hist("b"):normalize(12):rshift(12):denormalize():truncate(8):hist("b_atend"):lower():toDarkroom("b")
------------
ITYPE = types.array2d( types.uint(8), T )
inp = d.input( ITYPE )
out = d.apply( "a", d.map( a, T ), inp )
out = d.apply( "b", d.map( b, T ), out )
fn = d.lambda( "fixed_wide", inp, out )
------------
hsfn = d.makeHandshake(fn)

harness.axi( "fixed_wide_handshake", hsfn, "frame_128.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W,H)

fixed.printHistograms()