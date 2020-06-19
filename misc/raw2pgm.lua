local J = require "common"
local ffi = require "ffi"

print("Usage: filename.raw out.pgm metadatafile.lua")
-- if bitsPerPixel>8, the bytes are just written out next to each other...

local infile = arg[1]
local filename = arg[2]
local metadata = dofile(arg[3])

local W,H,bitspp
if type(metadata.outputs)=="table" then
  bitspp = metadata.outputs[1].bitsPerPixel
  W = metadata.outputs[1].W
  H = metadata.outputs[1].H

  if type(metadata.outputWidth)=="string" then
    assert(false)
  end
else
  bitspp = metadata.outputBitsPerPixel
  W = metadata.outputWidth
  H = metadata.outputHeight
end

ffi.cdef[[
typedef struct {} FILE;

           FILE *fopen(const char *filename, const char *mode);
           int fprintf(FILE *stream, const char *format, ...);
           int fclose(FILE *stream);
           int fseek(FILE *stream, long int offset, int whence);
           size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
           size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);

         ]]

local imgIn = ffi.C.fopen(infile,"rb")
if imgIn==nil then
  print("Error, file not found "..infile)
  os.exit(1)
end

J.err( bitspp%8==0, "bits per pixel must be byte aligned!")

local totalSize=W*H*(bitspp/8)

local data = ffi.new("unsigned char["..(totalSize).."]")

local sz = ffi.C.fread(data,1,totalSize,imgIn)
if sz~=totalSize then
  print("File Size: "..tostring(sz)..", expected size:"..tostring(totalSize))
  print("file ",infile)
  print( "Incorrect file size!")
  os.exit(1)
end

local outfile = ffi.C.fopen(filename,"wb")
ffi.C.fprintf(outfile,"P5 "..(W*(bitspp/8)).." "..H.." 255 ")
ffi.C.fwrite(data,totalSize,1,outfile)
ffi.C.fclose(outfile)
ffi.C.fclose(imgIn)
