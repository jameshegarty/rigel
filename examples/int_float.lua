local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"
local G = require "generators.core"

-- hardfloat doesn't work with this on
R.default_nettype_none = false

W = 64
H = 32
T = 2

------------
local a = G.SchedulableFunction{"a",types.int(32), function(i) return G.Float(G.FloatRec{32}(i)) end}
------------
ITYPE = types.array2d( types.int(32), T )
inp = R.input( types.rv(types.Par(ITYPE)) )
out = R.apply( "a", G.Map{a}, inp )
fn = RM.lambda( "fixed_wide", inp, out )
------------
hsfn = RM.makeHandshake(fn)

local OTYPE = types.array2d(types.Float32,T)

harness{ outFile="int_float", fn=hsfn, inFile="trivial_64.raw", inSize={W,H}, outSize={W,H} }
