local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local harness = require "generators.harness"
--local fixed = require "fixed_float"
local G = require "generators.core"
local C = require "generators.examplescommon"

W = 64
H = 32
T = 2

------------
local a = G.SchedulableFunction{"a",types.int(32),
  function(i)
    local iflt = G.FloatRec{32}(i)
    local res = G.MulF(iflt,iflt)
    return G.Float(res)
  end}

------------
ITYPE = types.array2d( types.int(32), T )
inp = R.input( types.rv(types.Par(ITYPE)) )
out = R.apply( "a", G.Map{a}, inp )
out = C.bitcast( types.Array2d(types.Float32,2), types.Array2d(types.uint(8),8))(out)
fn = RM.lambda( "fixed_wide", inp, out )
------------
hsfn = RM.makeHandshake(fn)

harness{ outFile="float_mult", fn=hsfn, inFile="trivial_64.raw", inSize={W,H}, outSize={W*4,H}, outP=8 }
