local R = require "rigel"
local RM = require "modules"
local types = require("types")
local C = require("examplescommon")
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
inp = R.input( ITYPE )
local aout = R.apply( "a", afn, inp )
local inv = R.apply("inv", lutinv, aout)
out = R.apply( "b", bfn, R.tuple("binp",{inp,inv}) )
fn = RM.lambda( "fixed_wide", inp, out )
------------
hsfninp = R.input(R.Handshake(types.array2d(ITYPE,T)))
local out = R.apply("reducerate", RM.liftHandshake(RM.changeRate(ITYPE,1,T,1)), hsfninp )
local out = R.apply("idx", RM.makeHandshake(RM.index(types.array2d(types.uint(8),1),0)), out)
local out = R.apply("inner", RM.makeHandshake(fn), out )
local out = R.apply("A0", RM.makeHandshake(C.arrayop(ITYPE,1,1)), out)
local out = R.apply("incrate", RM.liftHandshake(RM.changeRate(ITYPE,1,1,8)), out )
local hsfn = RM.lambda("hsfn",hsfninp,out)

harness.axi( "fixed_inv_wide_handshake", hsfn, "frame_128.raw", nil, nil, types.array2d(ITYPE,T), T,W,H, types.array2d(ITYPE,T),T,W,H)
