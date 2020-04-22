local rigel = require "rigel"
rigel.MONITOR_FIFOS = true
local R = require "rigelSimple"
local types = require "types"
local J = require "common"

dofile("moduleparams_core.lua")

local configs = {}
local meta = {}

configs.padSeq = J.cartesian{type=Type, size={IS}, V=NumP, pad=LRBT, value={0,18}}
meta.padSeq={}
for k,v in ipairs(configs.padSeq) do
  if v.type==types.bool() then v.value=true end
  if v.type:isArray() or v.type:isTuple() then v.value={v.value} end
  v.pad = J.shallowCopy(v.pad)
  for i=1,4 do if v.pad[i]%v.V~=0 then  v.pad[i]=J.upToNearest(v.V,v.pad[i]) end end

  meta.padSeq[k]={inputP=v.V, outputP=v.V, inputImageSize=v.size}
  meta.padSeq[k].outputImageSize={v.size[1]+v.pad[1]+v.pad[2], v.size[2]+v.pad[3]+v.pad[4]}

end

runTests( configs, meta )

file = io.open("out/moduleparams_padseq.compiles.txt", "w")
file:write("Hello World")
file:close()
