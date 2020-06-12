local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local harness = require "generators.harness"
local harris = require "harris_core"
local fixed = require "fixed_float"
local C = require "generators.examplescommon"
local G = require "generators.core"

W = 32
H = 16

T = 8
ITYPE = types.array2d(types.uint(8),T)

------------
local function makeDisplay(ty)
  local ainp = fixed.parameter("ainp",ty)
  local a = (ainp*fixed.constant(1000)):lower(types.uint(8))
  local out = fixed.array2d({a},1,1):toRigelModule("a")
  return out
end

------------

local inpraw = R.input(R.Handshake(ITYPE))
local inp = R.apply("reducerate", RM.changeRate(types.uint(8),1,8,1), inpraw )

local dxdyfn, dxdyType = harris.makeDXDY(W,H)
local dxdy = R.apply("dxdy",dxdyfn,inp)
dxdy = G.Index{{0,0}}(dxdy)

local out = harris.HarrisKernel(dxdy)
out = G.Float(out)
out = G.Fmap{C.bitcast( types.Float32, types.Array2d(types.uint(8),4))}(out)

fn = RM.lambda( "harris", inpraw, out )

harness{outFile="harris", fn=fn, inFile="box_32_16.raw", inSize={W,H}, outSize={W*4,H}, outP=4 }
