local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local harness = require "generators.harness"
local G = require "generators.core"
local C = require "generators.examplescommon"

-- hardfloat doesn't work with this on
R.default_nettype_none = false

W = 64
H = 32
T = 2

------------
local a = G.SchedulableFunction{"a",types.int(32),
  function(i)
    local lhs = G.FloatRec{32}(i)
    local rhs = G.FloatRec{32}(G.Const{types.Float32,345.456}(G.ValueToTrigger(i)))
    local res = G.SubF(lhs,rhs)
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

harness{ outFile="float_sub", fn=hsfn, inFile="trivial_64.raw", inSize={W,H}, outSize={W*4,H}, outP=8 }
