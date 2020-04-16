local rigel = require "rigel"
rigel.MONITOR_FIFOS = false
local R = require "rigelSimple"
local types = require "types"
local J = require "common"

dofile("moduleparams_core.lua")

local configs = {}
local meta = {}

configs.downsampleSeq = J.cartesian{type=Type, size={IS}, V=NumP, scale={ {1,1},{2,1},{1,2},{2,2} } }
meta.downsampleSeq = {}
for k,v in ipairs(configs.downsampleSeq) do
  meta.downsampleSeq[k] = {inputP=v.V, outputP=v.V, inputImageSize=v.size}
  meta.downsampleSeq[k].outputImageSize={v.size[1]/v.scale[1], v.size[2]/v.scale[2]}
end

runTests( configs, meta )

file = io.open("out/moduleparams_downsample.compiles.txt", "w")
file:write("Hello World")
file:close()
