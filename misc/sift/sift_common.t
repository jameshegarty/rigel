local common = {}

common.TILES_X=4
common.TILES_Y=4

common.C = terralib.includecstring([[
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

]], {"-Wno-nullability-completeness"})


terra common.DOT(a:&float,b:&float)
  var sum : float = 0
  for i=0,common.TILES_X*common.TILES_Y*8 do
    if common.C.isNAN(a[i])==0 and common.C.isNAN(b[i])==0 then
      sum = sum + a[i]*b[i]
    end
  end
  return sum
end

terra common.SAD(a:&float,b:&float)
  var sum : float = 0
  for i=0,common.TILES_X*common.TILES_Y*8 do
    var d = a[i]-b[i]
    if d<0 then d=-d end
    sum = sum + d
  end
--  C.printf("SAD %f\n",sum)
  return sum
end

common.DESC_SIZE = common.TILES_X*common.TILES_Y*8+2

return common
