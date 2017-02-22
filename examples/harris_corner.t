local R = require "rigel"
local RM = require "modules"
local types = require("types")
local harness = require "harness"
local harris = require "harris_core"

W = 256
H = 256

T = 8
ITYPE = types.array2d(types.uint(8),T)

local inpraw = R.input(R.Handshake(ITYPE))
local inp = R.apply("reducerate", RM.liftHandshake(RM.changeRate(types.uint(8),1,8,1)), inpraw )
local harrisFn = harris.makeHarris(W,H,false)
local out = R.apply("filterfn", harrisFn, inp )
local out = R.apply("incrate", RM.liftHandshake(RM.changeRate(types.uint(8),1,1,8)), out )
fn = RM.lambda( "harris", inpraw, out )

--harness.axi( "harris_corner", fn, "box_256.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W,H)
harness{ outFile="harris_corner", fn=fn, inFile="box_256.raw", inSize={W,H}, outSize={W,H} }