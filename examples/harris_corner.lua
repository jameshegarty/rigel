local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local harness = require "generators.harness"
local harris = require "harris_core"

W = 256
H = 256

T = 8
ITYPE = types.array2d(types.uint(8),T)

local inpraw = R.input(R.Handshake(ITYPE))
local inp = R.apply("reducerate", RM.changeRate(types.uint(8),1,8,1), inpraw )
local harrisFn = harris.makeHarris(W,H,false)
local out = R.apply("filterfn", harrisFn, inp )
local out = R.apply("incrate", RM.changeRate(types.uint(8),1,1,8), out )
fn = RM.lambda( "harris", inpraw, out )

harness{ outFile="harris_corner", fn=fn, inFile="box_256.raw", inSize={W,H}, outSize={W,H} }
