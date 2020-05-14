local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local harness = require "generators.harness"
local G = require "generators.core"

W = 64
H = 32
T = 2

local fn = G.Function{"fn",types.RV(types.Float32),
function(i)
  local tmp = G.ConcatConst{ types.Float32, 2.74435 }(i)
  tmp = G.TupleToArray(tmp)
  tmp = G.Map{G.FtoFR}(tmp)
  tmp = G.ArrayToTuple(tmp)
  tmp = G.DivF(tmp)
  tmp = G.Float(tmp)
  return G.Bitcast{types.Array2d(types.Uint(8),4)}(tmp)
end}

harness{ outFile="float_div", fn=fn, inFile="trivial_64.raw", inSize={W,H}, outSize={W*4,H}, outP=4 }
