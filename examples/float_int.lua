local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"
local G = require "generators.core"

-- hardfloat doesn't work with this on
R.default_nettype_none = false

W = 128
H = 64
--T = 2

------------
local a = G.Function{"a",types.rv(types.uint(8)),
                     function(i)
                       local tmp = G.FloatRec{32}(i)
                       return G.FtoU{8}(G.MulF{1/2}(tmp)) end}
--------------
--ITYPE = types.array2d( types.int(32), T )
--inp = R.input( types.rv(types.Par(ITYPE)) )
--out = R.apply( "a", G.Map{a}, inp )
--fn = RM.lambda( "fixed_wide", inp, out )
------------
hsfn = RM.makeHandshake(a)

--local OTYPE = types.array2d(types.Float32,T)

harness{ outFile="float_int", fn=hsfn, inFile="trivial_64.raw", inSize={W,H}, outSize={W,H} }
