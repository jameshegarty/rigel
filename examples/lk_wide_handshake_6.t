d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
C = require "examplescommon"
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"

if string.find(arg[0],"float") then
  f = require "fixed_float"
else
  f = require "fixed"
  f.DEEP_MULTIPLY = true
end

local W = 128
local H = 128
--T = 8

-- lk_full is 584x388, 2 channel

local window = 6

local T = 4
local RW_TYPE = types.array2d(types.array2d(types.uint(8),2),T)


require "lk_core"

bits = {
  inv22={15,26,0},
  inv22inp={0,10,0},
  d={0,0,0},
  Apartial={0,0,0},
  Bpartial={0,0,0},
  solve={0,0,0}
}

if f.FLOAT then
  harness.terraOnly( "lk_wide_handshake_6_float", LKTop(W,H,window,bits), "trivial_128.raw", nil, nil, RW_TYPE, T,W,H, RW_TYPE,T,W,H)
else
  harness.axi( "lk_wide_handshake_6", LKTop(W,H,window,bits), "trivial_128.raw", nil, nil, RW_TYPE, T,W,H, RW_TYPE,T,W,H)
end