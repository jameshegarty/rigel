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
  if string.find(arg[0],"axi") then
    -- don't use this multiplier in simulator - too slow!
    f.DEEP_MULTIPLY = true
  end
end

local W = 128
local H = 128
--T = 8

-- lk_full is 584x388, 2 channel

local window = 4

local T = 4
local RW_TYPE = types.array2d(types.array2d(types.uint(8),2),T)


require "lk_tr_core"

bits = {
  inv22={15,26,0},
  inv22inp={5,5,0}, -- NOTICE THIS IS DIFFERENT THAN WINDOW=6 VERSION
  d={0,0,0},
  Apartial={0,0,0},
  Bpartial={0,0,0},
  solve={0,0,0}
}

internalT = 1/4

if f.FLOAT then
  harness.terraOnly( "lk_tr_handshake_4_float", LKTop(internalT,W,H,window,bits), "trivial_128.raw", nil, nil, RW_TYPE, T,W,H, RW_TYPE,T,W,H)
else
  harness.axi( "lk_tr_handshake_4_4"..sel(f.DEEP_MULTIPLY,"_axi",""), LKTop(internalT,W,H,window,bits), "trivial_128.raw", nil, nil, RW_TYPE, T,W,H, RW_TYPE,T,W,H)
end