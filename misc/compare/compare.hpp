#include <stdio.h>
#include <map>
#include <string>

using namespace std;

typedef struct{
  FILE* file;
  int seenPixels;
  int w;
  int h;
} Filestate;

static map<string,Filestate> state;

// pixels: # of pixels being written this time
void writeBytes(string id, int w, int h, string type, int pixels, int bytecnt, unsigned char* data){
#ifndef DISABLE_WRITE_PIXELS
  if(state.count(id)==0){
    // initialize
    Filestate fs;
    string outfile=string("out/")+id+string(".raw");
    fs.file = fopen(outfile.c_str(),"wb");
    if(fs.file==NULL){printf("compare.hpp: could not open %s\n",outfile.c_str()); exit(1);}
    fs.seenPixels = 0;
    fs.w=w;
    fs.h=h;
    state.insert(pair<string,Filestate>(id,fs));

    //
    string outfileMD=string("out/")+id+string(".metadata.lua");
    FILE* md = fopen(outfileMD.c_str(),"w");
    if(md==NULL){printf("compare.hpp: could not open %s\n",outfileMD.c_str()); exit(1);}
    fprintf(md,"return {width=%d,height=%d,type='%s'}",w,h,type.c_str());
    fclose(md);
  }

  if(state[id].seenPixels>w*h){
    printf("Error, more pixels written than expected! file:%s\n",id.c_str());
    //exit(1);
  }

  if(state[id].w!=w || state[id].h!=h){
    printf("Error, image size changed file:%s old:%d,%d new:%d,%d\n",id.c_str(),state[id].w,state[id].h,w,h);
  }
  
  state[id].seenPixels+=pixels;
  for(int i=0; i<bytecnt; i++){fputc(data[i],state[id].file);}
#endif
}

void done(){
  map<string,Filestate>::iterator it;
  
  for ( it = state.begin(); it != state.end(); it++ ){
    if(it->second.seenPixels != it->second.w*it->second.h){
      printf("Error, image %s is missing pixels\n", it->first.c_str() );
    }
    
    fclose(it->second.file);
  }
}

void writePixel(string id, int w, int h, unsigned short value){
  writeBytes(id,w,h,"uint16",1,2,(unsigned char*)&value);
}

void writePixel(string id, int w, int h, unsigned int value){
  writeBytes(id,w,h,"uint32",1,4,(unsigned char*)&value);
}

void writePixel(string id, int w, int h, unsigned char value){
  writeBytes(id,w,h,"uint8",1,1,(unsigned char*)&value);
}

void writePixel(string id, int w, int h, float value){
  writeBytes(id,w,h,"float",1,4,(unsigned char*)&value);
}

void writePixel(string id, int w, int h, unsigned long value){
  writeBytes(id,w,h,"uint64",1,8,(unsigned char*)&value);
}

void writePixel(string id, int w, int h, int value){
  writeBytes(id,w,h,"int32",1,4,(unsigned char*)&value);
}


void writePixel(string id, int w, int h, bool value){
  unsigned char v = 0;
  if(value){v=255;}
  writeBytes(id,w,h,"bool",1,1,&v);
}
