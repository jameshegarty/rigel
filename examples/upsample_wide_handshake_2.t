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

  local hsfn =  d.upsampleSeq( types.uint(8), W, H, T, scaleX, scaleX) 

  harness.axi( "upsample_wide_handshake_"..scaleX, hsfn, ITYPE, nil, nil, W,H, ITYPE,W*scaleX,H*scaleX)
end

local t = string.sub(arg[0],string.find(arg[0],"%d+"))
MAKE(tonumber(t))