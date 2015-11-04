local d = require "darkroom"
local C = require "examplescommon"
local harness = require "harness"
local f = require "fixed"


local makeStereo = require "stereo_tr_core"

--local filename = "medi"
--local W = 360
--local H = 203
local OffsetX = 20
--local SADRadius = 4
local SADWidth = 8
--local SearchWindow = 64
local A = types.uint(8)

local reducePrecision = 16


local T = string.sub(arg[0],string.find(arg[0],"%d+")) -- throughput #
local filename = string.sub(arg[0],#arg[0]-6-#T,#arg[0]-3-#T)

local W = 360
local H = 203
local SearchWindow = 64

if filename=="tiny" then
  -- fast version for automated testing
  W,H = 256,16
  SearchWindow = 4
elseif filename=="medi" then
  W,H = 352,200
  SearchWindow = 64
else
  print("UNKNOWN FILENAME "..filename)
  assert(false)
end

local hsfn = makeStereo(filename,1/tonumber(T),W,H,A,SearchWindow,SADWidth,OffsetX, reducePrecision, 0)

local ATYPE = types.array2d(A,2)
local ITYPE = types.array2d(ATYPE,4)
local OUT_TYPE = types.array2d(types.uint(8),8)
harness.axi( "stereo_tr_"..filename.."_"..T, hsfn,"stereo_"..filename..".raw",nil, nil,  ITYPE,  4, W, H, OUT_TYPE, 8, W, H )
