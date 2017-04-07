require "comparecommon"

if type(arg[4])~="string" then
  print("usage: diff.lua reference.raw reference.metadata.lua test.raw test.metadata.lua [acceptedError]")
  os.exit(1)
end

--print("Load Reference")
local refData, refMetadata, refPixelCount = loadRigelImage(arg[1],arg[2])
--print("Load Test")
local testData, testMetadata, testPixelCount = loadRigelImage(arg[3],arg[4])

if refMetadata.width ~= testMetadata.width or refMetadata.height ~= testMetadata.height then
  print("Diff error: image size mismatch, reference="..tostring(refMetadata.width).."x"..tostring(refMetadata.height).." test="..tostring(testMetadata.width).."x"..tostring(testMetadata.height))
  os.exit(1)
end

assert(refPixelCount==testPixelCount)

local diffImagePtr = ffi.new("double["..refPixelCount.."]")

local errorSum = 0
local errorSumNoInf = 0

for i=0,refPixelCount-1 do
  local delta = testData[i]-refData[i]
  errorSum = errorSum + math.abs(delta)

  
  local valid = true
  -- exclude infs
  if refData[i]==1/0 or refData[i]==-1/0 or refData[i]~=refData[i] then valid=false end
  
  if valid then
    errorSumNoInf = errorSumNoInf + math.abs(delta)
    if math.abs(delta)>0 and arg[5]~=nil then
      if math.abs(delta)>(2/32) then
--        print("MISMATCH",i,"ref",refData[i],"test",testData[i],"delta",math.abs(delta))
      end
    end
  end
end

if errorSum~=0 then print("Error Sum",errorSum) end
if errorSumNoInf~=0 then print("Error Sum (no inf, no nan)",errorSumNoInf) end

if errorSum~=0 and (arg[5]==nil or errorSumNoInf>tonumber(arg[5])) then
  os.exit(1)
end
