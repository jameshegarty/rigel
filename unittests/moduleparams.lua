local R = require "rigelSimple"
local types = require "types"
local J = require "common"

dofile("moduleparams_core.lua")

local configs = {}
local meta = {}


configs.upsampleSeq = J.cartesian{type=Type, size={IS}, V=NumP, scale={ {1,1},{2,1},{1,2},{2,2} } }
meta.upsampleSeq = {}
for k,v in ipairs(configs.upsampleSeq) do
  meta.upsampleSeq[k] = {inputP=v.V, outputP=v.V, inputImageSize=v.size}
  meta.upsampleSeq[k].outputImageSize={v.size[1]*v.scale[1], v.size[2]*v.scale[2]}
end

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

local cropAmt = { {1,1,1,1}, {0,2,0,2}, {2,0,0,2}, {0,0,0,0} }
configs.cropSeq = J.cartesian{type=Type, size={IS}, V=NumP, crop=cropAmt }
meta.cropSeq={}
for k,v in ipairs(configs.cropSeq) do
  v.crop = J.shallowCopy(v.crop)
  for i=1,4 do if v.crop[i]%v.V~=0 then  v.crop[i]=J.upToNearest(v.V,v.crop[i]) end end
    
  meta.cropSeq[k] = { inputP=v.V, outputP=v.V, inputImageSize=v.size }
  meta.cropSeq[k].outputImageSize={v.size[1]-v.crop[1]-v.crop[2], v.size[2]-v.crop[3]-v.crop[4]}
end

configs.changeRate = J.cartesian{type=Type, H={1}, inW=NumP, outW=NumP}
meta.changeRate={}
for k,v in ipairs(configs.changeRate) do
  meta.changeRate[k] = {inputP=v.inW, outputP=v.outW, inputImageSize=IS, outputImageSize=IS}
end

configs.constSeq = {}
local CSC = J.cartesian{type=Type, W=NumP, H=NumP, P=NumP, value={42}}
meta.constSeq={}
for k,v in ipairs(CSC) do
  if v.P <= v.W then
    local val = v.value
    if v.type:isArray() or v.type:isTuple() then val={val} end
    v.value = J.broadcast(val,v.W*v.H)
    
    v.type = types.array2d(v.type,v.W,v.H)
    --v.P = 1/v.P
    v.W=nil; v.H=nil

    table.insert(configs.constSeq, v)
    meta.constSeq[#configs.constSeq] = {inputP=0, outputP=v.type:channels()/v.P, outputImageSize=IS, inputImageSize=IS}
  end
end

configs.sub = {{inType=types.int(8),outType=types.int(8)}}
meta.sub={{inputP=1,outputP=1,inputImageSize={32,32},outputImageSize={32,32}}}

configs.rcp = {{type=types.uint(8)}}
meta.rcp={{inputP=1,outputP=1,inputImageSize=IS,outputImageSize=IS}}

runTests( configs, meta )

file = io.open("out/moduleparams.compiles.txt", "w")
file:write("Hello World")
file:close()
