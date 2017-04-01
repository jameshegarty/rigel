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

for i=0,pixelCount-1 do
  local px = dataPtr[i]

  sum = sum + px
  
  if maxValue==nil or px>maxValue then maxValue=px end
  if minValue==nil or px<minValue then minValue=px end

  if px~=math.floor(px) then fractionalCount = fractionalCount + 1 end

  local fracBits = 0
  local fpx = px
  while fpx~=math.floor(fpx) do fracBits=fracBits+1; fpx = fpx*2 end
  if fracBits>maxFracBits then maxFracBits=fracBits end
end

print("Max Value",maxValue)
print("Min Value",minValue)
print("SUM",sum)
print("Pixel Count",pixelCount)
print("# of non-integer pixels",fractionalCount)
print("Max Fractional Bits",maxFracBits)
local maxabs = math.max( math.abs(maxValue), math.abs(minValue) )
print("Max Integer Bits", math.ceil(math.log(maxabs)/math.log(2)) )
