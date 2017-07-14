local R = require "rigel"
local RM = require "modules"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"

W = 128
H = 64

local scale = tonumber(string.sub(arg[0],string.find(arg[0],"%d+")))

------------
inp = R.input( types.array2d(types.uint(8),W,H) )
b = R.apply("b", RM.upsample( types.uint(8), W,H, scale,scale) , inp)
p100 = RM.lambda( "p100", inp, b )
------------
hsfn = RM.makeHandshake(p100)

harness{ outFile="upsample_"..tostring(scale), fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W*scale,H*scale} }
