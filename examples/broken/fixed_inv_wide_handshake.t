local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local C = require("examplescommon")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"
local fixed = require "fixed"

W = 128
H = 64
T = 8

------------
local ainp = fixed.parameter("ainp",types.uint(8))
--local a = (ainp:lift(0)*ainp:lift(0)*fixed.constant(256,false,9,-8)):hist("a_norm")
local a = (ainp:lift(0)*ainp:lift(0)):hist("a_norm")
a = a:toSigned()
local afn = a:toDarkroom("a")
------------
local lutinv, lutinvtype = C.lutinvert(a.type)
print("LUTINV TYPE",lutinvtype)
------------
local binp = fixed.parameter("binp", types.tuple{types.uint(8),lutinvtype} )
local b_orig = binp:index(0)
local b_inv = binp:index(1)
local constv = fixed.constant(2048, true)
print("CONST",constv.type)
local b_orig = b_orig:lift(0):toSigned()
local b = (b_inv*b_orig)*constv -- should now be (2048/x)
--b = b:normalize(20):truncate(8):lower()
b = b:abs():denormalize():truncate(8):lower()
local bfn = b:toDarkroom("b")
------------
ITYPE = types.uint(8)
inp = d.input( ITYPE )
local aout = d.apply( "a", afn, inp )
local inv = d.apply("inv", lutinv, aout)
out = d.apply( "b", bfn, d.tuple("binp",{inp,inv}) )
fn = d.lambda( "fixed_wide", inp, out )
------------
hsfninp = d.input(d.Handshake(types.array2d(ITYPE,T)))
local out = d.apply("reducerate", d.liftHandshake(d.changeRate(ITYPE,1,T,1)), hsfninp )
local out = d.apply("idx", d.makeHandshake(d.index(types.array2d(types.uint(8),1),0)), out)
local out = d.apply("inner", d.makeHandshake(fn), out )
local out = d.apply("A0", d.makeHandshake(C.arrayop(ITYPE,1,1)), out)
local out = d.apply("incrate", d.liftHandshake(d.changeRate(ITYPE,1,1,8)), out )
local hsfn = d.lambda("hsfn",hsfninp,out)

harness.axi( "fixed_inv_wide_handshake", hsfn, "frame_128.raw", nil, nil, types.array2d(ITYPE,T), T,W,H, types.array2d(ITYPE,T),T,W,H)
