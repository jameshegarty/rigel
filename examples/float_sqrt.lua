local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local harness = require "generators.harness"
--local fixed = require "fixed_float"
local G = require "generators.core"
local C = require "generators.examplescommon"

W = 64
H = 32
T = 1

------------
--local ainp = fixed.parameter("ainp",types.int(32))
--local af = ainp:lift(0) 
--local a = (af-fixed.constant(6540982534034)):toRigelModule("a")
--local a = (af:sqrt()):toRigelModule("a")
--local a = (aa):toRigelModule("a")
local a = G.SchedulableFunction{"a",types.int(32),
                                function(i)
--                                  i = G.Print{"INP"}(i)
    local iflt = G.FloatRec{32}(i)
    local res = G.SqrtF(iflt)
    local ret =  G.Float(res)
--    ret = G.Print{"RET"}(ret)
    return ret
  end}

------------
ITYPE = types.array2d( types.int(32), T )
inp = R.input( types.RV(types.Par(ITYPE)) )
out = R.apply( "a", a, inp[0] )
out = G.Fmap{C.bitcast(types.Float32,types.Array2d(types.Uint(8),4))}(out)
fn = RM.lambda( "fixed_wide", inp, out )
------------

harness{ outFile="float_sqrt", fn=fn, inFile="trivial_64.raw", inSize={W,H}, outSize={W*4,H}, outP=4 }
