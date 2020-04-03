local RM = require "generators.modules"
local C = require "generators.examplescommon"
local types = require("types")
local harness = require "generators.harness"

W = 128
H = 64
T = 8

------------
function MAKE(scaleX)
  local ITYPE = types.array2d( types.uint(8), T ) -- always 8 for AXI
  local hsfn = C.downsampleSeq( types.uint(8), W, H, T, scaleX, scaleX)

  harness{ outFile="downsample_wide_handshake_"..scaleX, fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W/scaleX,H/scaleX} }
end

local t = string.sub(arg[0],string.find(arg[0],"%d+"))
MAKE(tonumber(t))
