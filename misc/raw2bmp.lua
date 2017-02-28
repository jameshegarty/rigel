darkroom={}
require("common")
--Image = require("image")
--cstdlib = terralib.includec("stdlib.h")
--cstdio = terralib.includec("stdio.h")
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

  --unsigned int totalsize=width * height * 3 +54; // we always write 3 channels
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
    
  --unsigned int owidth=width;
  local owidth = ffi.new("unsigned int[1]",width)
  --unsigned int oheight=height;
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
  --unsigned short int planes=1;
  local planes = ffi.new("unsigned short[1]",1)
    
  if ((ffi.C.fwrite(planes, 2, 1, file)) ~= 1) then
    print("Error writeing planes");
    return 0;
  end
    
  --// write the bpp
  --unsigned short bitsPP = 24;
  local bitsPP = ffi.new("unsigned short[1]",24)
    
  if ((ffi.C.fwrite(bitsPP, 2, 1, file)) ~= 1) then
    print("[Bmp save] Error writeing bpp");
    return 0;
  end
    
  --//compression
  --unsigned int comp=0;
  local comp = ffi.new("unsigned int[1]",0)
    
  if ((ffi.C.fwrite(comp, 4, 1, file)) ~= 1) then
    print("Error writeing planes to ");
    return 0;
  end
    
  --//imagesize
  --comp=0;
  comp[0]=0
    
  if ((ffi.C.fwrite(comp, 4, 1, file)) ~= 1) then
    print("Error writeing planes to ");
    return 0;
  end
    
  --//XpixelsPerM
  --comp=0;
  comp[0]=0
    
  if ((ffi.C.fwrite(comp, 4, 1, file)) ~= 1) then
    print("Error writeing planes to ");
    return 0;
  end
    
  --//YpixelsPerM
  --comp=0;
  comp[0]=0
    
  if ((ffi.C.fwrite(comp, 4, 1, file)) ~= 1) then
    print("Error writeing planes to ");
    return 0;
  end
    
  --//ColorsUsed
  --comp=0;
  comp[0]=0
    
  if ((ffi.C.fwrite(comp, 4, 1, file)) ~= 1) then
    print("Error writeing planes to ");
    return 0;
  end
    
  --//ColorsImportant
  --comp=0;
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
    
  --unsigned char temp;

  --// bmps pad each row to be a multiple of 4 bytes
  --int padding = 4 - (width * 3 % 4); // we always write 3 channels
  local padding = 4 - (width * 3 % 4)
  --padding = padding == 4 ? 0 : padding;
  if padding==4 then padding=0 end
  --char pad[]={0,0,0};
  local pad = ffi.new("char[3]")
  pad[0]=0; pad[1]=0; pad[2]=0;

  if(channels==3)then
    -- calculate the size (assuming 24 bits or 3 bytes per pixel).
    --unsigned long size = height * width * channels;
    local size = height * width * channels;

    --unsigned char* tempData = malloc(sizeof(unsigned char)*width*height*3);
    local tempData = ffi.new("unsigned char["..tostring(width*height*3).."]")

    --for (unsigned int y=0; y<height; y++) then -- reverse all of the colors. (bgr -> rgb)
    for y=0,height-1 do
      --for (unsigned int x=0; x<width*3; x+=3)then
      for x=0,width*3-1,3 do
        local i=y*width*3+x;
        local ii = y*stride*3+x;
        tempData[i] = data[ii+2];
        tempData[i+1] = data[ii+1];
        tempData[i+2] = data[ii];
      end
    end
    
    if(padding ~= 0)then
      --for(int h=0; h<height; h++)then
      for h=0,height-1 do
        ffi.C.fwrite(tempData[h*width*channels], width*channels, 1, file);
        ffi.C.fwrite(pad,padding,1,file);
      end
    else
      if ((ffi.C.fwrite(tempData, size, 1, file)) ~= 1) then
        print("[Bmp save] Error writeing image data");
        return 0;
      end
    end

    --free(tempData);
      
  elseif channels==1 then
    --//we need to expand an alpha into 3 components so taht it can actually be read
    --unsigned char* expanded=malloc(sizeof(unsigned char)*width*height*3);
      local expanded = ffi.new("unsigned char["..tostring(width*height*3).."]")
      
    --for(int y=0; y<height; y++)then
    for y=0,height-1 do
      --for(int x=0; x<width; x++)then
      for x=0,width-1 do
        local i = (y*width+x)*3;
        local ii = y*stride+x;
        expanded[i]=data[ii];
        expanded[i+1]=data[ii];
        expanded[i+2]=data[ii];
      end
    end
       
    if(padding ~= 0)then
      --for(int h=0; h<height; h++)then
      for h=0,height-1 do
        ffi.C.fwrite(expanded[h*width*3], width*3, 1, file);
        ffi.C.fwrite(pad,padding,1,file);
      end
    else
      if ((ffi.C.fwrite(expanded,width*height*3, 1, file)) ~= 1) then
        print("[Bmp save] Error writing image data");
        --//delete[] expanded;
        --free(expanded);
        return 0;
      end
    end

    --//delete[] expanded;
    --free(expanded);
  else
    print("Error, image has %d channels!\n",channels);
    --assert(0); 
    return 0
  end
    
    
  ffi.C.fclose(file);

--  // were done.
  return 1;

--  return file
end

--[==[
local chack = terralib.includecstring [=[
#include<stdio.h>
#include <string.h>
#include <stdlib.h>
#include <assert.h>

int bsaveBMP_UC(void* ifile, int width, int height, int stride, int channels, void* idata){

  FILE* file = ifile;
  unsigned char* data = idata;
//  FILE *file;
    
  // make sure the file is there.
//  if ((file = fopen(filename, "wb"))==NULL){
//    printf("could't open file for writing %s",filename);
//    return 0;
//  }
    
//  unsigned char BMPheader[2]={66,77};

//  if ((fwrite(&BMPheader, sizeof(BMPheader), 1, file)) != 1) {
//    printf("[Bmp::save] Error writing header");
//    return 0;
//  }
    
  unsigned int totalsize=width * height * 3 +54; // we always write 3 channels
    
//  if ((fwrite(&totalsize, sizeof(totalsize), 1, file)) != 1) {
//    printf("[Bmp::save] Error writing header");
//    return 0;
//  }

  totalsize=0;
    
  if ((fwrite(&totalsize, sizeof(totalsize), 1, file)) != 1) {
    printf("[Bmp::save] Error writing header");
      
    return 0;
      
  }
    
  //offset to data=54
  totalsize=54;
    
  if ((fwrite(&totalsize, sizeof(totalsize), 1, file)) != 1) {
    printf("[Bmp::save] Error writing header");
      
    return 0;
      
  }
    
  //	Size of InfoHeader =40 
  totalsize=40;
    
  if ((fwrite(&totalsize, sizeof(totalsize), 1, file)) != 1) {
    printf("[Bmp::save] Error writeing header");
      
    return 0;
      
  }
    
  unsigned int owidth=width;
  unsigned int oheight=height;
    
  // write the width
  if ((fwrite(&owidth, 4, 1, file)) != 1) {
    printf("Error writeing width");
      
    return 0;
      
  }
    
  // write the height 
  if ((fwrite(&oheight, 4, 1, file)) != 1) {
    printf("Error writing height");
      
    return 0;
  }
    
    
  // write the planes
  unsigned short int planes=1;
    
  if ((fwrite(&planes, 2, 1, file)) != 1) {
    printf("Error writeing planes");
      
    return 0;
  }
    
  // write the bpp
  unsigned short bitsPP = 24;
    
  if ((fwrite(&bitsPP, 2, 1, file)) != 1) {
    printf("[Bmp save] Error writeing bpp");
    return 0;
  }
    
  //compression
  unsigned int comp=0;
    
  if ((fwrite(&comp, 4, 1, file)) != 1) {
    printf("Error writeing planes to ");
    return 0;
  }
    
  //imagesize
  comp=0;
    
  if ((fwrite(&comp, 4, 1, file)) != 1) {
    printf("Error writeing planes to ");
    return 0;
  }
    
  //XpixelsPerM
  comp=0;
    
  if ((fwrite(&comp, 4, 1, file)) != 1) {
    printf("Error writeing planes to ");
    return 0;
  }
    
  //YpixelsPerM
  comp=0;
    
  if ((fwrite(&comp, 4, 1, file)) != 1) {
    printf("Error writeing planes to ");
    return 0;
  }
    
  //ColorsUsed
  comp=0;
    
  if ((fwrite(&comp, 4, 1, file)) != 1) {
    printf("Error writeing planes to ");
    return 0;
  }
    
  //ColorsImportant
  comp=0;
     
  if ((fwrite(&comp, 4, 1, file)) != 1) {
    printf("Error writeing planes to ");
    return 0;
  }
    
  // read the data. 
    
  if (data == NULL) {
    printf("[Bmp save] No image data to write!");
    return 0;	
  }
    
  unsigned char temp;

  // bmps pad each row to be a multiple of 4 bytes
  int padding = 4 - (width * 3 % 4); // we always write 3 channels
  padding = padding == 4 ? 0 : padding;
  char pad[]={0,0,0};

  if(channels==3){
    // calculate the size (assuming 24 bits or 3 bytes per pixel).
    unsigned long size = height * width * channels;

    unsigned char* tempData = malloc(sizeof(unsigned char)*width*height*3);

    for (unsigned int y=0; y<height; y++) { // reverse all of the colors. (bgr -> rgb)
      for (unsigned int x=0; x<width*3; x+=3){
        int i=y*width*3+x;
        int ii = y*stride*3+x;
        tempData[i] = data[ii+2];
        tempData[i+1] = data[ii+1];
        tempData[i+2] = data[ii];
      }
    }
    
    if(padding != 0){
      for(int h=0; h<height; h++){
        fwrite(&tempData[h*width*channels], width*channels, 1, file);
        fwrite(pad,padding,1,file);
      }
    }else{
      if ((fwrite(tempData, size, 1, file)) != 1) {
        printf("[Bmp save] Error writeing image data");
        return 0;
      }
    }

    free(tempData);
      
  }else if(channels==1){
    //we need to expand an alpha into 3 components so taht it can actually be read
    //unsigned char* expanded=new unsigned char[width*height*3];
    unsigned char* expanded=malloc(sizeof(unsigned char)*width*height*3);
      
    for(int y=0; y<height; y++){
      for(int x=0; x<width; x++){
        int i = (y*width+x)*3;
        int ii = y*stride+x;
        expanded[i]=data[ii];
        expanded[i+1]=data[ii];
        expanded[i+2]=data[ii];
      }
    }
       
    if(padding != 0){
      for(int h=0; h<height; h++){
        fwrite(&expanded[h*width*3], width*3, 1, file);
        fwrite(pad,padding,1,file);
      }
    }else{
      if ((fwrite(expanded,width*height*3, 1, file)) != 1) {
        printf("[Bmp save] Error writing image data");
        //delete[] expanded;
        free(expanded);
        return 0;
      }
    }

    //delete[] expanded;
    free(expanded);
  }else{
    printf("Error, image has %d channels!\n",channels);
    assert(0); 
  }
    
    
  fclose(file);

  // were done.
  return 1;
}
]=]

]==]

function raw2bmp(infile, outfile, axiround)
  local totalSize = metadata.outputWidth*metadata.outputHeight*metadata.outputBytesPerPixel
  local dataPtr = ffi.new("unsigned char["..totalSize.."]")

  local imgIn = ffi.C.fopen(infile,"rb")
  if imgIn==nil then
    print("Error, file not found "..infile)
    os.exit(1)
  end
  
  local expectedOutputSize = metadata.outputWidth*metadata.outputHeight*metadata.outputBytesPerPixel
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
    print("File Size: "..sz..", expected size:"..expectedOutputSize)
    print( "Incorrect file size!")
    os.exit(1)
  end


  ffi.C.fclose(imgIn)

  -- we can't write 3 channels per pixel over axi.
  if metadata.outputBytesPerPixel==2 then
    --inp:addChannels(1)
    assert(false)
  elseif metadata.outputBytesPerPixel==4 then
    --inp:addChannels(-1)
    assert(false)
  end

  local file = writeBmp(outfile,metadata.outputWidth, metadata.outputHeight, metadata.outputWidth,
                     metadata.outputBytesPerPixel, dataPtr)

--  chack.bsaveBMP_UC(file, metadata.outputWidth, metadata.outputHeight, metadata.outputWidth,
--                    metadata.outputBytesPerPixel, dataPtr)
end

raw2bmp(arg[1], arg[2], arg[4]=="1")