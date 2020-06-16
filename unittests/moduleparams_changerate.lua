local rigel = require "rigel"
rigel.MONITOR_FIFOS = false
local R = require "rigelSimple"
local types = require "types"
local J = require "common"

dofile("moduleparams_core.lua")

local configs = {}
local meta = {}

configs.changeRate = J.cartesian{type=Type, H={1}, inW=NumP, outW=NumP}
meta.changeRate={}
for k,v in ipairs(configs.changeRate) do
  meta.changeRate[k] = {inputP=v.inW, outputP=v.outW, inputImageSize=IS, outputImageSize=IS}
end

runTests( configs, meta )

file = io.open("out/moduleparams_changerate.compiles.txt", "w")
file:write("Hello World")
file:close()
