local C = require "examplescommon"
local harness = require "harness"
local f = require "fixed"
local types = require "types"

local makeStereo = require "stereo_tr_core"
--local makeStereo = require "stereo_core"

local OffsetX = 60
local SADWidth = 16

local A = types.uint(8)

local reducePrecision = 16


--local T = string.sub(arg[0],string.find(arg[0],"%d+")) -- throughput #
--local filename = string.sub(arg[0],#arg[0]-6-#T,#arg[0]-3-#T)
local T = 8

local W = 640
local H = 480
local SearchWindow = 16

local infile = "ov7660_pair_far.raw"


local THRESH = -134*16
--THRESH=0

local hsfn = makeStereo( 1/tonumber(T), W, H, A, SearchWindow, SADWidth, OffsetX, reducePrecision, THRESH, true, false)
--local hsfn = makeStereo(W,H,OffsetX,SearchWindow,SADWidth,false, THRESH)

local ATYPE = types.array2d(A,2)
local ITYPE = types.array2d(ATYPE,4)
local OUT_TYPE = types.array2d(types.array2d(types.uint(8),4),2)

local outfile = "stereo_ov7660"
harness.axi( outfile, hsfn, infile, nil, nil,  ITYPE, 4, W, H, OUT_TYPE, 2, W, H )
