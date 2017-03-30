ffi = require "ffi"

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
  
  if metadata.type=="uint16" then
    bytes=2
  elseif metadata.type=="float" then
    bytes=4
  else
    print("Unknown type "..metadata.type)
    os.exit(1)
  end
  
  
  local pixelCount = metadata.width*metadata.height
  local byteCount = metadata.width*metadata.height*bytes
  
  local dataPtr
  
  if metadata.type=="uint16" then
    dataPtr = ffi.new("unsigned short["..pixelCount.."]")
  elseif metadata.type=="float" then
    dataPtr = ffi.new("float["..pixelCount.."]")
  else
    print("Unknown type "..metadata.type)
    os.exit(1)
  end
  
  local sz = ffi.C.fread(dataPtr,bytes,pixelCount,imgIn)
  
  if sz~=pixelCount then
    print("File Size: "..tostring(sz)..", expected size:"..tostring(pixelCount))
    print( "Incorrect file size!")
    os.exit(1)
  end

  ffi.C.fclose(imgIn)

  return dataPtr, metadata, pixelCount
end
