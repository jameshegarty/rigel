local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
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

local inpraw = d.input(d.Handshake(ITYPE))
local inp = d.apply("reducerate", d.liftHandshake(d.changeRate(types.uint(8),1,8,1)), inpraw )

local dxdyfn, dxdyType = harris.makeDXDY(W,H)
local dxdy = d.apply("dxdy",dxdyfn,inp)
local dxdy = d.apply("dxidx",d.makeHandshake(d.index(types.array2d(types.tuple{dxdyType,dxdyType},1),0,0)),dxdy)

local harrisFn, harrisType = harris.makeHarrisKernel(dxdyType,dxdyType)
local out = d.apply("harris", d.makeHandshake(harrisFn), dxdy)
out = d.apply("AO",d.makeHandshake(C.arrayop(harrisType,1,1)),out)
--local out = d.apply("MD", d.makeHandshake(makeDisplay(harrisType)), out)
local out = d.apply("incrate", d.liftHandshake(d.changeRate(OTYPE,1,1,OT)), out )
fn = d.lambda( "harris", inpraw, out )

harness.axi( "harris", fn, "box_32_16.raw", nil, nil, ITYPE, T,W,H, types.array2d(OTYPE,OT),OT,W,H)