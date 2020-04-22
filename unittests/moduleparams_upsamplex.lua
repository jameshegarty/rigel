local rigel = require "rigel"
rigel.MONITOR_FIFOS = false
local R = require "rigelSimple"
local types = require "types"
local J = require "common"

dofile("moduleparams_core.lua")

local configs = {}
local meta = {}

configs.upsampleXSeq = J.cartesian{type=Type, V=NumP, scale={2,4,8} }
meta.upsampleXSeq = {}
for k,v in ipairs(configs.upsampleXSeq) do
  meta.upsampleXSeq[k] = {inputP=v.V, outputP=v.V, inputImageSize=IS}
  meta.upsampleXSeq[k].outputImageSize={IS[1]*v.scale, IS[2]}
end

runTests( configs, meta )

file = io.open("out/moduleparams_upsamplex.compiles.txt", "w")
file:write("Hello World")
file:close()
