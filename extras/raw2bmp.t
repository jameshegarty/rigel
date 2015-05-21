darkroom={}
require("common")
Image = require("image")
cstdlib = terralib.includec("stdlib.h")
cstdio = terralib.includec("stdio.h")

local metadata = dofile(arg[3])

terra raw2bmp(infile : &int8, outfile : &int8)
  cstdio.printf("START RAW@BMP\n")
  var inp : Image
--  inp:loadRaw(infile,128,64,8)
  var totalSize = metadata.width*metadata.height*metadata.bytesPerChannel*metadata.channels
  inp.dataPtr = cstdlib.malloc(totalSize)
  inp.data = [&uint8](inp.dataPtr)

  var imgIn = cstdio.fopen(infile, "rb");
  cstdio.fread(inp.dataPtr,1,totalSize,imgIn)
  cstdio.fclose(imgIn)
  inp.width = metadata.width
  inp.height = metadata.height
  inp.stride = metadata.width
  inp.channels = metadata.channels
  inp.bits = 8
  inp.floating = false
  inp.SOA = false
  inp.sparse = false
  inp.isSigned = false

  cstdio.printf("%d %d %d %d\n",inp.width,inp.height,inp.channels,totalSize)
  -- remember: when using the simulator, the raw file you send in has to be upside down (bottom left pixels comes first
  -- thus, image is flipped). It turns out this is the same convention as BMP, so no flip at the end is necessary.
--  inp:flip()
  inp:save(outfile)
end

raw2bmp(arg[1], arg[2])