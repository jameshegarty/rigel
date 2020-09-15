local R = require "rigel"
R.AUTO_FIFOS = false
local RM = require "generators.modules"
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"
local J = require "common"

-- hardfloat doesn't work with this on
R.default_nettype_none = false

GRAD_INT = true
GRAD_SCALE = 4 -- <2 is bad
GRAD_TYPE = types.int(8)

local sift = require "sift_core_hw"

function doit( full, TILES )
  local W = 256
  local H = 256

  local MHz = nil

  if full then W,H = 1920,1080 end

  local T = 8

  local FILTER_FIFO = 512
  local OUTPUT_COUNT = 614

  if full then OUTPUT_COUNT = 3599 end
  local FILTER_RATE = {OUTPUT_COUNT,W*H}

  local ITYPE = types.array2d(types.uint(8),T)
  local siftFn, siftType = sift.siftTop( W, H, T, FILTER_RATE, FILTER_FIFO, TILES, TILES )
  local OTYPE = types.array2d(siftType,2)

  if full and TILES==4 then
    MHz = 115
  end
  
  local outfile = "sift_hw_"..tostring(TILES)..J.sel(full,"_1080p","")
  harness{ outFile=outfile, fn=siftFn, inFile=J.sel(full,"boxanim0000.raw","boxanim_256.raw"), inSize={W,H}, outSize={(TILES*TILES*8+2)*4,OUTPUT_COUNT}, outP=8, MHz=MHz }

  io.output("out/"..outfile..".design.txt"); io.write("SIFT "..TILES..J.sel(full," 1080p","")); io.close()
  io.output("out/"..outfile..".designT.txt"); io.write( 0.5 ); io.close()
  io.output("out/"..outfile..".dataset.txt"); io.write("SIG16_zu9"); io.close()
end

local first,flen = string.find(arg[0],"%d+")
local TILES = tonumber(string.sub(arg[0],first,flen))

doit( string.find(arg[0],"1080p")~=nil, TILES )
