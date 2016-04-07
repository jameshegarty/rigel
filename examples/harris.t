local R = require "rigel"
local RM = require "modules"
local types = require("types")
local harness = require "harness"
local harris = require "harris_core"
local fixed = require "fixed_float"
local C = require "examplescommon"

W = 32
H = 16

T = 8
ITYPE = types.array2d(types.uint(8),T)

--local OT = 8
--OTYPE = types.uint(8)

OT=2
OTYPE = types.float(32)
------------
local function makeDisplay(ty)
  local ainp = fixed.parameter("ainp",ty)
  local a = (ainp*fixed.constant(1000)):lower(types.uint(8))
  local out = fixed.array2d({a},1,1):toDarkroom("a")
  return out
end

------------

local inpraw = R.input(R.Handshake(ITYPE))
local inp = R.apply("reducerate", RM.liftHandshake(RM.changeRate(types.uint(8),1,8,1)), inpraw )

local dxdyfn, dxdyType = harris.makeDXDY(W,H)
local dxdy = R.apply("dxdy",dxdyfn,inp)
local dxdy = R.apply("dxidx",RM.makeHandshake(RM.index(types.array2d(types.tuple{dxdyType,dxdyType},1),0,0)),dxdy)

local harrisFn, harrisType = harris.makeHarrisKernel(dxdyType,dxdyType)
local out = R.apply("harris", RM.makeHandshake(harrisFn), dxdy)
out = R.apply("AO",RM.makeHandshake(C.arrayop(harrisType,1,1)),out)
local out = R.apply("incrate", RM.liftHandshake(RM.changeRate(OTYPE,1,1,OT)), out )
fn = RM.lambda( "harris", inpraw, out )

harness.axi( "harris", fn, "box_32_16.raw", nil, nil, ITYPE, T,W,H, types.array2d(OTYPE,OT),OT,W,H)