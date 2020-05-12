local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local harness = require "generators.harness"
local sift = require "sift_core"
local C = require "generators.examplescommon"
local G = require "generators.core"

local W = 16
local H = 16

local T = 8

-- # of tiles in X and Y
local TILES_X = 4
local TILES_Y = 4

local first,flen = string.find(arg[0],"%d+")
if first~=nil then
  TILES_X = tonumber(string.sub(arg[0],first,flen))
  TILES_Y = tonumber(string.sub(arg[0], string.find(arg[0],"%d+",flen+1)))
end

print("TILES:",TILES_X,TILES_Y)

local ITYPE = types.array2d(types.uint(8),T)
local siftFn, siftType = sift.siftDesc( W, H, T, TILES_X, TILES_Y )

print("SIFTYPE",siftType)

OTYPE = types.array2d(siftType,2)

------------
-- pad out to axi burst size
local inp = R.input( R.Handshake(ITYPE) )
local out = R.apply("SFT",siftFn,inp)

--local out = R.apply("PS", RM.liftHandshake( RM.padSeq(siftType, 2+8*TILES_X*TILES_Y, 1, 2, 0, 256-2-8*TILES_X*TILES_Y, 0, 0, 0)), out )
--print("OUT",out.type)
out = RM.makeHandshake(C.bitcast(types.Array2d(types.Float32,2),types.Array2d(types.Uint(8),8)))(out)
local hsfn = RM.lambda("sdf",inp,out)
---------

local extra = ""
if TILES_X~=4 or TILES_Y~=4 then extra="_"..TILES_X.."_"..TILES_Y end
harness{ outFile="sift_desc"..extra, fn=hsfn, inFile="desc.raw", inSize={W,H}, outSize={(2+8*TILES_X*TILES_Y)*4,1}, outP=8 }
