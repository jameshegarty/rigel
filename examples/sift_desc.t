local R = require "rigel"
local RM = require "modules"
local types = require("types")
local harness = require "harness"
local sift = require "sift_core"

local W = 16
local H = 16

local T = 8

local ITYPE = types.array2d(types.uint(8),T)
local siftFn, siftType = sift.siftDesc(W,H,T)

OTYPE = types.array2d(siftType,2)

------------
-- pad out to axi burst size
local inp = R.input( R.Handshake(ITYPE) )
local out = R.apply("SFT",siftFn,inp)
local out = R.apply("PS", RM.liftHandshake( RM.padSeq(siftType,130,1,2,0,126,0,0,0)), out )
local hsfn = RM.lambda("sdf",inp,out)
---------

--harness.terraOnly( "sift_desc", hsfn, "desc.raw", nil, nil, ITYPE, 8, W, H, OTYPE, 2, 256,1)
harness{ outFile="sift_desc", fn=hsfn, inFile="desc.raw", inSize={W,H}, outSize={256,1} }