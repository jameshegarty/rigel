local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require "harness"

function MAKE(T)
  assert(T<=1)


local ConvWidth = 4


  local sinp = S.parameter( "inp", types.array2d(types.uint(8),ConvWidth*T,ConvWidth) )
  local extract = d.lift( "extract", types.array2d(types.uint(8),ConvWidth*T,ConvWidth), types.uint(8), 1,
                          terra( a : &uint8[ConvWidth*T*ConvWidth], out : &uint8 )
  @out = (@a)[0]
end, sinp, S.index(sinp,0,0) )


local inputW = 128
local inputH = 64


local BASE_TYPE = types.array2d( types.uint(8), 1 )

--[=[
local ITYPE = d.StatefulV(BASE_TYPE)
local inp = d.input( ITYPE )

local out = d.apply( "convLB", d.stencilLinebufferPartial( types.uint(8), inputW, inputH, T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), inp)
out = d.apply("extract",d.RVPassthrough(d.makeStateful(extract)),out)
local lbp = d.lambda("lbp", inp, out)
local hsfn = d.liftHandshake(lbp)
]=]

local ITYPE = d.StatefulHandshake(BASE_TYPE)
local inp = d.input( ITYPE )

local out = d.apply( "convLB", d.stencilLinebufferPartial( types.uint(8), inputW, inputH, T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), inp)
out = d.apply("extract",d.makeHandshake(d.makeStateful(extract)),out)
local hsfn = d.lambda("lbp", inp, out)


harness.sim( "linebufferpartial_handshake_"..(1/T), hsfn, 1, BASE_TYPE, inputW, inputH, types.uint(8), inputW/T, inputH)
end

local t = string.sub(arg[0],string.find(arg[0],"%d+"))
MAKE(tonumber(1/t))