local R = require "rigel"
local RM = require "modules"
local C = require "examplescommon"
local types = require("types")
local harness = require "harness"

W = 128
H = 64
T = 8

--scaleX = 2
------------
function MAKE(scaleX)
  local ITYPE = types.array2d( types.uint(8), T ) -- always 8 for AXI

  local hsfn =  C.upsampleSeq( types.uint(8), W, H, T, scaleX, scaleX) 

  --harness.axi( "upsample_wide_handshake_"..scaleX, hsfn, "frame_128.raw", nil, nil, ITYPE,T,W,H, ITYPE,T,W*scaleX,H*scaleX)
  harness{ outFile = "upsample_wide_handshake_"..scaleX, fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W*scaleX,H*scaleX} }
end

local t = string.sub(arg[0],string.find(arg[0],"%d+"))
MAKE(tonumber(t))