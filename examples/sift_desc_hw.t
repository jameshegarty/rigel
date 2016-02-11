local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"

GRAD_INT = true
GRAD_SCALE = 4 -- <2 is bad
GRAD_TYPE = types.int(8)

local sift = require "sift_core_hw"
local C = require "examplescommon"

local W = 16
local H = 16

local T = 8

local ITYPE = types.array2d(types.uint(8),T)
local siftFn, siftType = sift.siftDesc(W,H,T)

OTYPE = types.array2d(siftType,2)

------------
-- pad out to axi burst size
local inp = d.input(d.Handshake(ITYPE))
local out = d.apply("SFT",siftFn,inp)
local out = d.apply("PS",d.liftHandshake(d.padSeq(siftType,130,1,2,0,126,0,0,0)),out)
local hsfn = d.lambda("sdf",inp,out)
---------

harness.axi( "sift_desc_hw", hsfn, "desc.raw", nil, nil, ITYPE, 8, W, H, OTYPE, 2, 256,1,nil,2000)