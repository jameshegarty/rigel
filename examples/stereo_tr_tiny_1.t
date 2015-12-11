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

local infile
local THRESH = 0
if filename=="tiny" then
  -- fast version for automated testing
  W,H = 256,16
  SearchWindow = 4
  infile = "stereo_tiny.raw"
elseif filename=="medi" then
  W,H = 352,200
  SearchWindow = 64
  infile = "stereo_medi.raw"
elseif filename=="full" then
  W, H = 720, 400
  SearchWindow = 64
  infile = "stereo0000.raw"
  THRESH = 1000
else
  print("UNKNOWN FILENAME "..filename)
  assert(false)
end

local hsfn = makeStereo(1/tonumber(T),W,H,A,SearchWindow,SADWidth,OffsetX, reducePrecision, THRESH, false)

local ATYPE = types.array2d(A,2)
local ITYPE = types.array2d(ATYPE,4)
local OUT_TYPE = types.array2d(types.uint(8),8)

local outfile = "stereo_tr_"..filename.."_"..T
harness.axi( outfile, hsfn, infile, nil, nil,  ITYPE, 4, W, H, OUT_TYPE, 8, W, H )
io.output("out/"..outfile..".design.txt"); io.write("Stereo "..SearchWindow.." "..SADWidth.."x"..SADWidth.." "..filename); io.close()
io.output("out/"..outfile..".designT.txt"); io.write(1/T); io.close()