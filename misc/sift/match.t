
SEARCH_FEATURES = arg[1]
W = tonumber(arg[2])
H = tonumber(arg[3])
TARGET_FEATURES = arg[4]
TARGET_W = tonumber(arg[5])
TARGET_H = tonumber(arg[6])
outputfile = arg[7]

print("USAGE: INFILE_features INFILE_W INFILE_H TARGET_features TARGET_W TARGET_H output")
print("INFILE_features are the features that come from INFILE")
print("TARGET_featuers are the thing we're searching for")

TILES_X=4
TILES_Y=4

C= terralib.includecstring [[
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

FILE* openImage(char* filename, unsigned int* numbytes){
  FILE* infile = fopen(filename, "rb");
  if(infile==NULL){
    printf("File not found %s\n",filename);
    exit(1);
  }
  fseek(infile, 0L, SEEK_END);
  *numbytes = ftell(infile);
  fseek(infile, 0L, SEEK_SET);

  return infile;
}

void loadImage(FILE* infile,  void* address, unsigned int numbytes){
  int outlen = fread(address, sizeof(char), numbytes, infile);
  if(outlen!=numbytes){
    printf("ERROR READING\n");
  }

  fclose(infile);
}


int saveImage(char* filename,  void* address, unsigned int numbytes){
  FILE* outfile = fopen(filename, "wb");
  if(outfile==NULL){
    printf("could not open for writing %s\n",filename);
    exit(1);
  }
  int outlen = fwrite(address,1,numbytes,outfile);
  if(outlen!=numbytes){
    printf("ERROR WRITING\n");
  }

  fclose(outfile);
}

int isNAN(float a){
  if(a!=a){
return 1;
}else{
return 0;
}
}

                            ]]


terra DOT(a:&float,b:&float)
  var sum : float = 0
  for i=0,TILES_X*TILES_Y*8 do
    if C.isNAN(a[i])==0 and C.isNAN(b[i])==0 then
      sum = sum + a[i]*b[i]
    end
  end
  return sum
end

terra SAD(a:&float,b:&float)
  var sum : float = 0
  for i=0,TILES_X*TILES_Y*8 do
    var d = a[i]-b[i]
    if d<0 then d=-d end
    sum = sum + d
  end
--  C.printf("SAD %f\n",sum)
  return sum
end

DESC_SIZE = TILES_X*TILES_Y*8+2

terra match()
  var f0 : &C.FILE
  var f0_len : uint32
  f0 = C.openImage( SEARCH_FEATURES, &f0_len )
  var f0_data : &float = [&float](C.malloc(f0_len))
  C.loadImage( f0, f0_data, f0_len )

  if f0_len%(DESC_SIZE*4)~=0 then
    C.printf("Strange search file length (%d)\n",f0_len)
  --  C.exit(1)
  end

  var searchCnt = (f0_len-(f0_len%(DESC_SIZE*4)))/(DESC_SIZE*4)

  var f1 : &C.FILE
  var f1_len : uint32
  f1 = C.openImage( TARGET_FEATURES, &f1_len )
  var f1_data : &float = [&float](C.malloc(f1_len))
  C.loadImage( f1, f1_data, f1_len )

  if f1_len%(DESC_SIZE*4)~=0 then
    C.printf("Strange target file length\n")
    --C.exit(1)
  end

  var targetCnt = (f1_len-(f1_len%(DESC_SIZE*4)))/(DESC_SIZE*4)

  C.printf("SearchCount %d TargetCount %d\n",searchCnt, targetCnt)

  var bestMatch : &int = [&int](C.malloc(searchCnt*sizeof(int)))
  var bestMatchDist : &float = [&float](C.malloc(searchCnt*sizeof(float)))

  var max : float = 0
  var min : float = 10000000.f
  for S=0,searchCnt do
    var set : bool = false
    for T=0,targetCnt do
      var A = &f0_data[S*DESC_SIZE+2]
      var B = &f1_data[T*DESC_SIZE+2]
      var d = DOT(A,B)

      if (set==false or d>bestMatchDist[S]) then
        bestMatch[S] = T
        bestMatchDist[S] = d
        set=true
      end
    end

    if bestMatchDist[S]>max then max=bestMatchDist[S] end
    if bestMatchDist[S]<min then min=bestMatchDist[S] end
  end

  C.printf("MAX %f MIN %f\n",max,min)

  var out = [&uint8](C.malloc(W*H*3))

  for y=0,H do
    for x=0,W do
      for c=0,3 do
        out[y*W*3+x*3+c] = 0
      end
    end
  end

  for S=0,searchCnt do
    var T = bestMatch[S]
    var x = [int](f0_data[S*DESC_SIZE])
    var y = [int](f0_data[S*DESC_SIZE+1])

    var targetX = [int](f1_data[T*DESC_SIZE])
    var targetY = [int](f1_data[T*DESC_SIZE+1])
    
    var targetXPct = ([float](targetX)/[float](TARGET_W))*[float](255)
    var targetYPct = ([float](targetY)/[float](TARGET_H))*[float](255)

    out[y*W*3+x*3] = [uint8](targetXPct)
    out[y*W*3+x*3+1] = [uint8](targetYPct)

    var d = (bestMatchDist[S]-min)/(max-min)
    d = d * 255
    out[y*W*3+x*3+2] = d
  end

  C.saveImage(outputfile,out,W*H*3)
end

match()