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

local a = G.Function{"a",types.rv(types.uint(8)),
                     function(i)
                       local tmp = G.FloatRec{32}(i)
                       return G.FRtoU{8}(G.MulF{1/2}(tmp)) end}
hsfn = RM.makeHandshake(a)

harness{ outFile="float_int", fn=hsfn, inFile="trivial_64.raw", inSize={W,H}, outSize={W,H} }
