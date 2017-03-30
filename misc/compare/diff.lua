require "comparecommon"

if type(arg[4])~="string" then
  print("usage: diff.lua reference.raw reference.metadata.lua test.raw test.metadata.lua [diffimage.raw]")
  os.exit(1)
end

local refData, refMetadata, refPixelCount = loadRigelImage(arg[1],arg[2])
local testData, testMetadata, testPixelCount = loadRigelImage(arg[3],arg[4])

if refMetadata.width ~= testmetadata.width or refMetadata.height ~= testmetadata.height then
  print("Diff error: image size mismatch, reference="..tostring(refMetadata.width).."x"..tostring(refMetadata.height).." test="..tostring(testMetadata.width).."x"..tostring(testMetadata.height))
  os.exit(1)
end

assert(refPixelCount==testPixelCount)

local diffImagePtr = ffi.new("double["..refPixelCount.."]")

local errorSum = 0

for i=0,refPixelCount-1 do
  local delta = testData[i]-refData[i]
  errorSum = errorSum + math.abs(delta)
end

print("Error Sum",errorSum)

if errorSum~=0 then
  os.exit(1)
end
