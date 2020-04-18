local rigel = require "rigel"
rigel.MONITOR_FIFOS = true
local R = require "rigelSimple"
local types = require "types"
local J = require "common"

dofile("moduleparams_core.lua")

local configs = {}
local meta = {}

local cropAmt = { {1,1,1,1}, {0,2,0,2}, {2,0,0,2}, {0,0,0,0} }
configs.cropSeq = J.cartesian{type=Type, size={IS}, V=NumP, crop=cropAmt }
meta.cropSeq={}
for k,v in ipairs(configs.cropSeq) do
  v.crop = J.shallowCopy(v.crop)
  for i=1,4 do if v.crop[i]%v.V~=0 then  v.crop[i]=J.upToNearest(v.V,v.crop[i]) end end
    
  meta.cropSeq[k] = { inputP=v.V, outputP=v.V, inputImageSize=v.size }
  meta.cropSeq[k].outputImageSize={v.size[1]-v.crop[1]-v.crop[2], v.size[2]-v.crop[3]-v.crop[4]}
end

runTests( configs, meta )

file = io.open("out/moduleparams_cropseq.compiles.txt", "w")
file:write("Hello World")
file:close()
