darkroom={}
local J = require "common"
local err = J.err
ffi = require "ffi"

local metadata = dofile(arg[3])


ffi.cdef[[
typedef struct {} FILE;

           FILE *fopen(const char *filename, const char *mode);
           int fprintf(FILE *stream, const char *format, ...);
           int fclose(FILE *stream);
           int fseek(FILE *stream, long int offset, int whence);
           size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
           size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);

         ]]

-- add n channels
-- ** this can actually be used to delete channels too if n<0
--terra Image:addChannels(n:int)
function addChannels(n, width, height, stride, channels, bits, data)
  local size = width*height*(channels+n)*(bits/8)
  --var temp : &uint8
  --cstdlib.posix_memalign( [&&opaque](&temp), pageSize, size)
  local temp = ffi.new("unsigned char["..tostring(size).."]")

  err(stride==width," no stride allowed ")
  err(bits==8,"8 bit only")

  --var inF = [&uint8](self.data)

  local lineWidth = width*(channels+n)
  for y = 0, height-1 do
    for x = 0, width-1 do
      for c = 0, channels+n-1 do
        --var aa : uint8 = 0
        local aa = ffi.new("unsigned char[1]")
        if c<channels then
          aa[0] = data[y*channels*width + x*channels + c]
        end
        temp[y*lineWidth + x*(channels+n) + c] = aa[0]
      end
    end
  end

  --self:free()
  --self.data = temp
  --self.dataPtr = temp
  --self.channels = self.channels+n
  return temp
end

function writeBmp(filename,width,height,stride,channels,data)
  local file = ffi.C.fopen(filename,"wb")
  if file==nil then
    print("could't open file for writing ",filename);
    os.exit(1)
  end
  
  local BMPheader = ffi.new("unsigned char[2]")
  BMPheader[0]=66
  BMPheader[1]=77

  if ((ffi.C.fwrite(BMPheader, 2, 1, file)) ~= 1)  then
    print("[Bmp::save] Error writing header");
    return 0;
  end

  local totalsize=ffi.new("unsigned int[1]",width * height * 3 +54)
    
  if ((ffi.C.fwrite(totalsize, 4, 1, file)) ~= 1) then
    print("[Bmp::save] Error writing header");
    return 0;
  end

  totalsize[0]=0;
    
  if ((ffi.C.fwrite(totalsize, 4, 1, file)) ~= 1) then
    print("[Bmp::save] Error writing header");
      
    return 0;
      
  end
    
  --//offset to data=54
  totalsize[0]=54;
    
  if ((ffi.C.fwrite(totalsize, 4, 1, file)) ~= 1) then
    print("[Bmp::save] Error writing header");
    return 0;
  end
    
  --//	Size of InfoHeader =40 
  totalsize[0]=40;
    
  if ((ffi.C.fwrite(totalsize, 4, 1, file)) ~= 1) then
    print("[Bmp::save] Error writeing header");
    return 0;
  end
    
  local owidth = ffi.new("unsigned int[1]",width)
  local oheight = ffi.new("unsigned int[1]",height)
    
  --// write the width
  if ((ffi.C.fwrite(owidth, 4, 1, file)) ~= 1) then
    print("Error writing width");
    return 0;
  end
    
  --// write the height 
  if ((ffi.C.fwrite(oheight, 4, 1, file)) ~= 1) then
    print("Error writing height");
    return 0;
  end
    
    
  --// write the planes
  local planes = ffi.new("unsigned short[1]",1)
    
  if ((ffi.C.fwrite(planes, 2, 1, file)) ~= 1) then
    print("Error writeing planes");
    return 0;
  end
    
  --// write the bpp
  local bitsPP = ffi.new("unsigned short[1]",24)
    
  if ((ffi.C.fwrite(bitsPP, 2, 1, file)) ~= 1) then
    print("[Bmp save] Error writeing bpp");
    return 0;
  end
    
  --//compression
  local comp = ffi.new("unsigned int[1]",0)
    
  if ((ffi.C.fwrite(comp, 4, 1, file)) ~= 1) then
    print("Error writeing planes to ");
    return 0;
  end
    
  --//imagesize
  comp[0]=0
    
  if ((ffi.C.fwrite(comp, 4, 1, file)) ~= 1) then
    print("Error writeing planes to ");
    return 0;
  end
    
  --//XpixelsPerM
  comp[0]=0
    
  if ((ffi.C.fwrite(comp, 4, 1, file)) ~= 1) then
    print("Error writeing planes to ");
    return 0;
  end
    
  --//YpixelsPerM
  comp[0]=0
    
  if ((ffi.C.fwrite(comp, 4, 1, file)) ~= 1) then
    print("Error writeing planes to ");
    return 0;
  end
    
  --//ColorsUsed
  comp[0]=0
    
  if ((ffi.C.fwrite(comp, 4, 1, file)) ~= 1) then
    print("Error writeing planes to ");
    return 0;
  end
    
  --//ColorsImportant
  comp[0]=0
     
  if ((ffi.C.fwrite(comp, 4, 1, file)) ~= 1) then
    print("Error writeing planes to ");
    return 0;
  end
    
  --// read the data. 
    
  if (data == nil) then
    print("[Bmp save] No image data to write!");
    return 0;	
  end

  --// bmps pad each row to be a multiple of 4 bytes
  local padding = 4 - (width * 3 % 4)
  if padding==4 then padding=0 end
  local pad = ffi.new("char[3]")
  pad[0]=0; pad[1]=0; pad[2]=0;

  if(channels==3)then
    -- calculate the size (assuming 24 bits or 3 bytes per pixel).

    local size = height * width * channels;

    local tempData = ffi.new("unsigned char["..tostring(width*height*3).."]")


    for y=0,height-1 do
      for x=0,width*3-1,3 do
        local i=y*width*3+x;
        local ii = y*stride*3+x;
        tempData[i] = data[ii+2];
        tempData[i+1] = data[ii+1];
        tempData[i+2] = data[ii];
      end
    end
    
    if(padding ~= 0)then
      for h=0,height-1 do
        ffi.C.fwrite(tempData+(h*width*channels), width*channels, 1, file);
        ffi.C.fwrite(pad,padding,1,file);
      end
    else
      if ((ffi.C.fwrite(tempData, size, 1, file)) ~= 1) then
        print("[Bmp save] Error writeing image data");
        return 0;
      end
    end
      
  elseif channels==1 then
    --//we need to expand an alpha into 3 components so taht it can actually be read
    local expanded = ffi.new("unsigned char["..tostring(width*height*3).."]")
      
    for y=0,height-1 do
      for x=0,width-1 do
        local i = (y*width+x)*3;
        local ii = y*stride+x;
        expanded[i]=data[ii];
        expanded[i+1]=data[ii];
        expanded[i+2]=data[ii];
      end
    end
       
    if(padding ~= 0)then
      for h=0,height-1 do
        ffi.C.fwrite(expanded+(h*width*3), width*3, 1, file);
        ffi.C.fwrite(pad,padding,1,file);
      end
    else
      if ((ffi.C.fwrite(expanded,width*height*3, 1, file)) ~= 1) then
        print("[Bmp save] Error writing image data");
        return 0;
      end
    end

  else
    print("Error, image has %d channels!\n",channels);
    return 0
  end
    
    
  ffi.C.fclose(file);

  return 1;
end


function raw2bmp(infile, outfile, axiround)

  local outputBytesPerPixel = math.ceil(metadata.outputBitsPerPixel/8)
  --local inputBytesPerPixel = math.ceil(metadata.inputBitsPerPixel/8)
  
  -- special case: x86 has no 3 byte type, so round stuff in that range up to 4 bytes
  if metadata.outputBitsPerPixel>16 and metadata.outputBitsPerPixel<32 then
    outputBytesPerPixel = 4
  elseif metadata.outputBitsPerPixel>32 and metadata.outputBitsPerPixel<64 then
    outputBytesPerPixel = 8
  end

  --if metadata.inputBitsPerPixel>16 and metadata.inputBitsPerPixel<32 then
  --  inputBytesPerPixel = 4
  --end

  local totalSize = metadata.outputWidth*metadata.outputHeight*outputBytesPerPixel
  local dataPtr = ffi.new("unsigned char["..totalSize.."]")

  local imgIn = ffi.C.fopen(infile,"rb")
  if imgIn==nil then
    print("Error, file not found "..infile)
    os.exit(1)
  end
  
  local expectedOutputSize = metadata.outputWidth*metadata.outputHeight*outputBytesPerPixel
  if axiround then

    if expectedOutputSize % 128 ~=0 then
      print("Error, expected output size should be mod 128 (axi burst size)")
      os.exit(1)
    end

    -- include 1 AXI burst worth of metadata
    expectedOutputSize = expectedOutputSize+128
  end

  local sz = ffi.C.fread(dataPtr,1,totalSize,imgIn)

  if sz~=totalSize then
    print("File Size: "..tostring(sz)..", expected size:"..tostring(expectedOutputSize))
    print( "Incorrect file size!")
    os.exit(1)
  end

  ffi.C.fclose(imgIn)

  -- we can't write 3 channels per pixel over axi.
  if outputBytesPerPixel==2 then
    --inp:addChannels(1)
    --assert(false)
    dataPtr = addChannels(1, metadata.outputWidth, metadata.outputHeight, metadata.outputWidth, outputBytesPerPixel, 8, dataPtr)
    outputBytesPerPixel = 3
  elseif outputBytesPerPixel==1 or outputBytesPerPixel==3 then
    -- noop: natively supported
  elseif outputBytesPerPixel>=4 then
    -- just throw out the extra data!
    dataPtr = addChannels(3-outputBytesPerPixel, metadata.outputWidth, metadata.outputHeight, metadata.outputWidth, outputBytesPerPixel, 8, dataPtr)
    outputBytesPerPixel = 3
  else
    print("raw2bmp: unsupported output bytes per pixel ", outputBytesPerPixel)
    os.exit(1)
  end

  local file = writeBmp(outfile,metadata.outputWidth, metadata.outputHeight, metadata.outputWidth,
                     outputBytesPerPixel, dataPtr)
end

raw2bmp(arg[1], arg[2], arg[4]=="1")
