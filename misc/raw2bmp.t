darkroom={}
require("common")
Image = require("image")
cstdlib = terralib.includec("stdlib.h")
cstdio = terralib.includec("stdio.h")

local metadata = dofile(arg[3])

terra raw2bmp(infile : &int8, outfile : &int8, axiround:bool)
  cstdio.printf("START RAW@BMP\n")
  var inp : Image
--  inp:loadRaw(infile,128,64,8)
  var totalSize = metadata.outputWidth*metadata.outputHeight*metadata.outputBytesPerPixel
  inp.dataPtr = cstdlib.malloc(totalSize)
  inp.data = [&uint8](inp.dataPtr)

  var imgIn = cstdio.fopen(infile, "rb");

  cstdio.fseek(imgIn, 0, cstdio.SEEK_END);
  var sz = cstdio.ftell(imgIn);
  cstdio.fseek(imgIn, 0, cstdio.SEEK_SET);
  
  var expectedOutputSize = metadata.outputWidth*metadata.outputHeight*metadata.outputBytesPerPixel
  if axiround then
    --cstdio.printf("Round to AXI size\n")
    --expectedOutputSize = upToNearestTerra(128,expectedOutputSize) -- round to AXI burst size
    if expectedOutputSize % 128 ~=0 then
      cstdio.printf("Error, expected output size should be mod 128 (axi burst size)\n")
      cstdlib.exit(1)
    end

    -- include 1 AXI burst worth of metadata
    expectedOutputSize = expectedOutputSize+128
  end
  if sz~=expectedOutputSize then
    cstdio.printf("File Size: %d, expected size:%d\n",sz, expectedOutputSize)
    darkroomAssert(false, "Incorrect file size!")
  end

  cstdio.fread(inp.dataPtr,1,totalSize,imgIn)
  cstdio.fclose(imgIn)
  inp.width = metadata.outputWidth
  inp.height = metadata.outputHeight
  inp.stride = metadata.outputWidth
  inp.channels = metadata.outputBytesPerPixel
  inp.bits = 8
  inp.floating = false
  inp.SOA = false
  inp.sparse = false
  inp.isSigned = false

  -- we can't write 3 channels per pixel over axi.
  if inp.channels==2 then
    inp:addChannels(1)
  elseif inp.channels==4 then
    inp:addChannels(-1)
  end

  cstdio.printf("%d %d %d %d\n",inp.width,inp.height,inp.channels,totalSize)
  -- remember: when using the simulator, the raw file you send in has to be upside down (bottom left pixels comes first
  -- thus, image is flipped). It turns out this is the same convention as BMP, so no flip at the end is necessary.
--  inp:flip()
  inp:save(outfile)
end

raw2bmp(arg[1], arg[2], arg[4]=="1")