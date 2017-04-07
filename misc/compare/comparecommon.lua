ffi = require "ffi"
require "common"

ffi.cdef[[
typedef struct {} FILE;

           FILE *fopen(const char *filename, const char *mode);
           int fprintf(FILE *stream, const char *format, ...);
           int fclose(FILE *stream);
           int fseek(FILE *stream, long int offset, int whence);
           size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
           size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);

         ]]

function loadRigelImage(rawfile, metafile)
  local metadata = dofile(metafile)

  local imgIn = ffi.C.fopen(rawfile,"rb")
  if imgIn==nil then
    print("Error, file not found "..arg[1])
    os.exit(1)
  end

  local bytes
  local shift = 0
  local FFIDATATYPE
  
  if string.find(metadata.type,"int")~=nil then

    local bitstring
    local signed
    if string.find(metadata.type,"uint")~=nil then
      bitstring = metadata.type:sub(5)
      signed=false
    else
      bitstring = metadata.type:sub(4)
      signed = true
    end
    
    --print("bitstring",bitstring)

    local bits

    if string.find(metadata.type,"_")~=nil then
      -- this is a fixed type
      bitstring = explode("_",bitstring)
      bits = tonumber(bitstring[1])
      shift = tonumber(bitstring[2])
    else
      bits = tonumber(bitstring)
    end
    
    if bits<=8 then
      bytes = 1
      FFIDATATYPE = sel(signed,"char","unsigned char")
    elseif bits <=16 then
      bytes = 2
      FFIDATATYPE = sel(signed,"short","unsigned short")
    elseif bits <=32 then
      bytes = 4
      FFIDATATYPE = sel(signed,"int","unsigned int")
    elseif bits <=64 then
      bytes = 8
      FFIDATATYPE = sel(signed,"long","unsigned long")
    else
      assert(false)
    end
--  elseif metadata.type=="uint16" then
--    bytes=2
--    FFIDATATYPE = "unsigned short"
  elseif metadata.type=="float" then
    bytes=4
    FFIDATATYPE = "float"
  else
    print("Unknown type "..metadata.type)
    os.exit(1)
  end
  
  
  local pixelCount = metadata.width*metadata.height
  local byteCount = metadata.width*metadata.height*bytes
  
  local dataPtr = ffi.new(FFIDATATYPE.."["..pixelCount.."]")
  
  local sz = ffi.C.fread(dataPtr,bytes,pixelCount,imgIn)
  
  if sz~=pixelCount then
    print("Pixel Count: "..tostring(sz)..", expected pixel count:"..tostring(pixelCount))
    print( "Incorrect file size!")
    os.exit(1)
  end

  ffi.C.fclose(imgIn)

  -- do conversion
  if shift~=0 then
    local oldDataPtr = dataPtr
    dataPtr = ffi.new("double["..pixelCount.."]")
    local factor = math.pow(2,shift)

    for i=0,pixelCount-1 do
      dataPtr[i] = tonumber(oldDataPtr[i])*factor
    end
  end
  
  return dataPtr, metadata, pixelCount
end
