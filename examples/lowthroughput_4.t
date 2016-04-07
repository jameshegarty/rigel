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

harness.axi( "lowthroughput_"..factor, hsfn, "frame_128.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W,H)