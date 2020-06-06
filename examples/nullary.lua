local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local harness = require "generators.harness"
local C = require "generators.examplescommon"
local RS = require "rigelSimple"


W = 128
H = 64
T = 8

harness{ outFile="nullary", fn=RM.makeHandshake(RM.constSeq( {42,32,22,12}, types.uint(8), 4, 1, 1),nil,false,"Top" ), inFile="frame_128.raw", inSize={W,H}, outSize={W,H} }
