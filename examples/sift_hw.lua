local R = require "rigel"
R.AUTO_FIFOS = false
local RM = require "generators.modules"
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"
local J = require "common"

GRAD_INT = true
GRAD_SCALE = 4 -- <2 is bad
GRAD_TYPE = types.int(8)

local sift = require "sift_core_hw"

function doit(full)
  local W = 256
  local H = 256

  if full then W,H = 1920,1080 end

  local T = 8

  local FILTER_FIFO = 512
  local OUTPUT_COUNT = 614

  if full then OUTPUT_COUNT = 3599 end
  local FILTER_RATE = {OUTPUT_COUNT,W*H}

  local ITYPE = types.array2d(types.uint(8),T)
  local siftFn, siftType = sift.siftTop( W, H, T, FILTER_RATE, FILTER_FIFO, 4, 4 )
  local OTYPE = types.array2d(siftType,2)

  harness{ outFile="sift_hw"..J.sel(full,"_1080p",""), fn=siftFn, inFile=J.sel(full,"boxanim0000.raw","boxanim_256.raw"), inSize={W,H}, outSize={130*4,OUTPUT_COUNT}, outP=8 }

end

doit(string.find(arg[0],"1080p")~=nil)
