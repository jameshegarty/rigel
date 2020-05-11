local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local harness = require "generators.harness"
local fixed = require "fixed_float"

W = 64
H = 32
T = 2

------------
local ainp = fixed.parameter("ainp",types.int(32))
local af = ainp:lift(0) 
--local a = (af-fixed.constant(6540982534034)):toRigelModule("a")
local a = (af:invert()):toRigelModule("a")
--local a = (aa):toRigelModule("a")

------------
ITYPE = types.array2d( types.int(32), T )
inp = R.input( types.rv(types.Par(ITYPE)) )
out = R.apply( "a", RM.map( a, T ), inp )
fn = RM.lambda( "fixed_wide", inp, out )
------------
hsfn = RM.makeHandshake(fn)

local OTYPE = types.array2d(types.Float32,T)

harness{ outFile="fixed_float_inv", fn=hsfn, inFile="trivial_64.raw", inSize={W,H}, outSize={W,H} }
