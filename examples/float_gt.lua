local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local harness = require "generators.harness"
--local fixed = require "fixed_float"
local G = require "generators.core"

W = 64
H = 32
T = 2

------------
local a = G.Function{"a",types.rv(types.Int(32)),
  function(i)
    local iflt = G.FloatRec{32}(i)
    local c = G.FloatRec{32}(G.Const{types.uint(48),754098253}(G.ValueToTrigger(i)))
    local igt = G.GTF(iflt,c)
    return G.Sel(igt,R.c(255,types.U8),R.c(0,types.U8))
  end}

------------
ITYPE = types.array2d( types.int(32), T )
inp = R.input( types.rv(types.Par(ITYPE)) )
out = R.apply( "a", RM.map( a, T ), inp )
fn = RM.lambda( "fixed_wide", inp, out )
------------
hsfn = RM.makeHandshake(fn)

harness{ outFile="float_gt", fn=hsfn, inFile="trivial_64.raw", inSize={W,H}, outSize={W,H} }
