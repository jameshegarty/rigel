local rigel = require "rigel"
rigel.MONITOR_FIFOS = false
local R = require "rigelSimple"
local types = require "types"
local J = require "common"

dofile("moduleparams_core.lua")

local configs = {}
local meta = {}

configs.upsampleYSeq = J.cartesian{type=Type, size={IS}, V=NumP, scale={2,4,8} }
meta.upsampleYSeq = {}
for k,v in ipairs(configs.upsampleYSeq) do
  meta.upsampleYSeq[k] = {inputP=v.V, outputP=v.V, inputImageSize=v.size}
  meta.upsampleYSeq[k].outputImageSize={v.size[1], v.size[2]*v.scale}
end

runTests( configs, meta )

file = io.open("out/moduleparams_upsampley.compiles.txt", "w")
file:write("Hello World")
file:close()
