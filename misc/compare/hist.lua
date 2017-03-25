ffi = require "ffi"

if type(arg[3])~="string" then
  print("usage: hist.lua image.raw image.metadata.lua buckets")
  os.exit(1)
end

local metadata = dofile(arg[2])

ffi.cdef[[
typedef struct {} FILE;

           FILE *fopen(const char *filename, const char *mode);
           int fprintf(FILE *stream, const char *format, ...);
           int fclose(FILE *stream);
           int fseek(FILE *stream, long int offset, int whence);
           size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
           size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);

         ]]



local imgIn = ffi.C.fopen(arg[1],"rb")
if imgIn==nil then
  print("Error, file not found "..arg[1])
  os.exit(1)
end

local bytes

if metadata.type=="uint16" then
  bytes=2
else
  print("Unknown type "..metadata.type)
  os.exit(1)
end


local pixelCount = metadata.width*metadata.height*bytes

local dataPtr

if metadata.type=="uint16" then
  dataPtr = ffi.new("unsigned char["..pixelCount.."]")
else
  print("Unknown type "..metadata.type)
  os.exit(1)
end

local sz = ffi.C.fread(dataPtr,1,pixelCount,imgIn)

if sz~=pixelCount then
    print("File Size: "..tostring(sz)..", expected size:"..tostring(pixelCount))
    print( "Incorrect file size!")
    os.exit(1)
end

ffi.C.fclose(imgIn)

-- build histogram
local buckets = tonumber(arg[3])
print("BUCKETS",buckets)

local maxValue, minValue

for i=0,metadata.width*metadata.height do
  local px = dataPtr[i]

  if maxValue==nil or px>maxValue then maxValue=px end
  if minValue==nil or px<minValue then minValue=px end
end

print("MAX",maxValue)
print("MIN",minValue)