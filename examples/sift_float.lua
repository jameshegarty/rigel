local types = require("types")
local harness = require "generators.harness"
local sift = require "sift_core"

local W = 256
local H = 256

local T = 8

local FILTER_FIFO = 128
local FILTER_RATE = 128

local ITYPE = types.array2d(types.uint(8),T)
local siftFn, siftType = sift.siftTop(W,H,T,FILTER_RATE,FILTER_FIFO)
OTYPE = types.array2d(siftType,2)
--harness.terraOnly( "sift_float", siftFn, "box_256.raw", nil, nil, ITYPE, 8, W, H, OTYPE, 2, ((W*H)/FILTER_RATE)*130,1)
harness{ outFile="sift_float", fn=siftFn, inFile="box_256.raw", inSize={W,H}, outSize={((W*H)/FILTER_RATE)*130,1} }
