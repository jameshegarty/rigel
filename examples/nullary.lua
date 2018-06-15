local R = require "rigel"
local RM = require "modules"
local types = require("types")
local harness = require "harness"
local C = require "examplescommon"
local RS = require "rigelSimple"


W = 128
H = 64
T = 8

harness{ outFile="nullary", fn=RS.HS(RM.constSeq( {42,32,22,12}, types.uint(8), 4, 1, 1),false ), inFile="frame_128.raw", inSize={W,H}, outSize={W,H} }
