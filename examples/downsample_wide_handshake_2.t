local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"

W = 128
H = 64
T = 8

--scaleX = 2
------------
function MAKE(scaleX)
  local ITYPE = types.array2d( types.uint(8), T ) -- always 8 for AXI

  --local inp = d.input( d.StatefulHandshake(ITYPE) )
--  local out = d.apply("reducerate", d.liftHandshake(d.changeRate(types.uint(8),1,8,T)), inp )
  --out = d.apply("DS", d.liftHandshake(d.liftDecimate(d.downsampleXSeq( types.uint(8), W,H,T,scaleX))), out)
--  local downsampleT = math.max(T/scaleX,1)
--  out = d.apply("incrate", d.liftHandshake(d.changeRate(types.uint(8),1,downsampleT,8)), out )
  --local hsfn = d.lambda("hsfn", inp, out)
  local hsfn = d.liftHandshake( d.downsampleSeq( types.uint(8), W, H, T, scaleX, scaleX) )

  harness.axi( "downsample_wide_handshake_"..scaleX, hsfn, "frame_128.raw", nil, nil, ITYPE, T,W,H, ITYPE, T, W/scaleX,H/scaleX)
end

local t = string.sub(arg[0],string.find(arg[0],"%d+"))
MAKE(tonumber(t))