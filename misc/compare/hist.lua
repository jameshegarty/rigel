require "comparecommon"

if type(arg[2])~="string" then
  print("usage: hist.lua image.raw image.metadata.lua buckets")
  os.exit(1)
end

dataPtr, metadata, pixelCount = loadRigelImage(arg[1],arg[2])

-- build histogram
local buckets = tonumber(arg[3])
--print("BUCKETS",buckets)

local maxValue, minValue
local sum = 0
local fractionalCount = 0
local maxFracBits = 0
local infcnt = 0
local nancnt = 0

for i=0,pixelCount-1 do

  local px = dataPtr[i]

  if px~=px then
    nancnt = nancnt+1
  elseif px==(1/0) or px==(-1/0) then
    infcnt = infcnt+1
  else
    sum = sum + px
    
    if maxValue==nil or px>maxValue then maxValue=px end
    if minValue==nil or px<minValue then minValue=px end
    
    if px~=math.floor(px) then fractionalCount = fractionalCount + 1 end
    
    local fracBits = 0
    local fpx = px
    while fpx~=math.floor(fpx) do fracBits=fracBits+1; fpx = fpx*2 end
    if fracBits>maxFracBits then maxFracBits=fracBits end
  end
end

local function pct(x,y)
  return "("..tostring( math.ceil((x/y)*100)).."%)"
end

print("Max Value",maxValue)
print("Min Value",minValue)
print("SUM",sum)
print("Pixel Count",pixelCount)
print("# of non-integer pixels",fractionalCount,pct(fractionalCount,pixelCount))
print("Max Fractional Bits",maxFracBits)
local maxabs = math.max( math.abs(maxValue), math.abs(minValue) )
print("Max Integer Bits", math.ceil(math.log(maxabs)/math.log(2)) )
print("INF Count:",infcnt,pct(infcnt,pixelCount))
print("NAN Count:",nancnt,pct(nancnt,pixelCount))
