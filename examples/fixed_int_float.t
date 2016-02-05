local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"
local fixed = require "fixed_float"

W = 64
H = 32
T = 2

------------
local ainp = fixed.parameter("ainp",types.int(32))
local a = ainp:lift(0):toDarkroom("a")

------------
ITYPE = types.array2d( types.int(32), T )
inp = d.input( ITYPE )
out = d.apply( "a", d.map( a, T ), inp )
fn = d.lambda( "fixed_wide", inp, out )
------------
hsfn = d.makeHandshake(fn)

local OTYPE = types.array2d(types.float(32),T)
harness.axi( "fixed_int_float", hsfn, "trivial_64.raw", nil, nil, ITYPE, T,W,H, OTYPE,T,W,H)
