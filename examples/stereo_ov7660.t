local d = require "darkroom"
local C = require "examplescommon"
local harness = require "harness"
local f = require "fixed"


local makeStereo = require "stereo_tr_core"

local OffsetX = 20
local SADWidth = 8

local A = types.uint(8)

local reducePrecision = 16


--local T = string.sub(arg[0],string.find(arg[0],"%d+")) -- throughput #
--local filename = string.sub(arg[0],#arg[0]-6-#T,#arg[0]-3-#T)
local T = 8

local W = 640
local H = 480
local SearchWindow = 64

local infile = "ov7660_pair_far.raw"

local THRESH = -43*16

local hsfn = makeStereo(1/tonumber(T),W,H,A,SearchWindow,SADWidth,OffsetX, reducePrecision, THRESH)

local ATYPE = types.array2d(A,2)
local ITYPE = types.array2d(ATYPE,4)
local OUT_TYPE = types.array2d(types.uint(8),8)

local outfile = "stereo_ov7660"
harness.axi( outfile, hsfn, infile, nil, nil,  ITYPE, 4, W, H, OUT_TYPE, 8, W, H )
