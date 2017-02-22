local RM = require "modules"
local types = require("types")
local harness = require "harness"

W = 128
H = 64
T = 8

local factor = string.sub(arg[0],string.find(arg[0],"%d+"))
factor=tonumber(factor)
print("FACTOR",factor)

ITYPE = types.array2d(types.uint(8),8)
hsfn = RM.liftHandshake(RM.reduceThroughput(ITYPE,factor))

harness{ outFile="lowthroughput_"..factor, fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H} }