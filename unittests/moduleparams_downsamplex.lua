local rigel = require "rigel"
rigel.MONITOR_FIFOS = true
local R = require "rigelSimple"
local types = require "types"
local J = require "common"

dofile("moduleparams_core.lua")

local configs = {}
local meta = {}

configs.downsampleXSeq = J.cartesian{type=Type, size={IS}, V=NumP, scale={2,4,8} }
meta.downsampleXSeq = {}
for k,v in ipairs(configs.downsampleXSeq) do
  meta.downsampleXSeq[k] = {inputP=v.V, outputP=v.V, inputImageSize=v.size}
  meta.downsampleXSeq[k].outputImageSize={v.size[1]/v.scale, v.size[2]}
end

runTests( configs, meta )

file = io.open("out/moduleparams_downsamplex.compiles.txt", "w")
file:write("Hello World")
file:close()
