#include <verilated.h>
#include <iostream>
#include VERILATORFILE

unsigned int divCeil(unsigned int a, unsigned int b){
  float aa = a;
  float bb = b;
  return (unsigned int)(ceil(aa/bb));
}

void setValid(SData* signal, unsigned int databits, bool valid){
  // for this verilator data type, we should have < 16 bits
  assert(databits<=16);

  if(valid){
    *signal |= (1<<databits);
  }else{
    *signal = 0;
  }    
}

void setValid(IData* signal, unsigned int databits, bool valid){
  // for this verilator data type, we should have < 16 bits
  assert(databits<=32);

  if(valid){
    *signal |= (1<<databits);
  }else{
    *signal = 0;
  }    
}

template<int N>
void setValid(WData (*signal)[N], unsigned int databits, bool valid){
  int idx = databits/32; // floor

  if(valid){
    (*signal)[idx] |= (1<<(databits-idx*32));
  }else{
    unsigned int t = (1<<(databits-idx*32));
    (*signal)[idx] &= ~t;
  }    
}

bool getValid(SData* signal, unsigned int databits){
  // for this verilator data type, we should have < 16 bits
  assert(databits<16);
  return (*signal & (1<<databits)) != 0;
}

bool getValid(IData* signal, unsigned int databits){
  // for this verilator data type, we should have < 16 bits
  assert(databits<=32);
  return (*signal & (1<<databits)) != 0;
}

template<int N>
bool getValid(WData (*signal)[N], unsigned int databits){
  int idx = databits/32; // floor
  return ( (*signal)[idx] & (1<<(databits-idx*32)) ) != 0;
}
    
void setData(SData* signal, unsigned int databits, FILE* file){
  // for this verilator data type, we should have < 16 bits
  assert(databits<=16);

  int readBytes = divCeil(databits,8);

  *signal = 0;
  for(int i=0; i<readBytes; i++){
    // assume big endian in the file
    unsigned long inp = fgetc(file);
    *signal |= (inp << (readBytes-i-1)*8);
  }
}

void setData(IData* signal, unsigned int databits, FILE* file){
  // for this verilator data type, we should have < 16 bits
  assert(databits<=32);

  int readBytes = divCeil(databits,8);

  *signal = 0;
  for(int i=0; i<readBytes; i++){
    // assume big endian in the file
    unsigned long inp = fgetc(file);
    *signal |= (inp << (readBytes-i-1)*8);
  }
}

template<int N>
void setData(WData (*signal)[N], unsigned int databits, FILE* file){
  for(int j=0; j<2; j++){
    (*signal)[j]=0;
    for(int i=0; i<4; i++){
      unsigned long inp = fgetc(file);
      (*signal)[j] |= (inp << i*8);
    }
  }
}
    
void getData(SData* signal, unsigned int databits, FILE* file){
  // for this verilator data type, we should have < 16 bits
  assert(databits<=16);

  int readBytes = divCeil(databits,8);

  for(int i=0; i<readBytes; i++){
    // assume big endian in the file
    unsigned char ot = (*signal) >> (readBytes-i-1)*8;
    fputc(ot,file);
  }
}

void getData(IData* signal, unsigned int databits, FILE* file){
  // for this verilator data type, we should have < 16 bits
  assert(databits<=32);

  int readBytes = divCeil(databits,8);

  for(int i=0; i<readBytes; i++){
    // assume big endian in the file
    unsigned char ot = (*signal) >> (readBytes-i-1)*8;
    fputc(ot,file);
  }
}

template<int N>
void getData( WData (*signal)[N], unsigned int databits, FILE* file){
  for(int j=0; j<2; j++){
    for(int i=0; i<4; i++){
      unsigned char ot = (*signal)[j] >> (i*8);
      fputc(ot,file);
    }
  }
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv); 

  if(argc!=9){
    printf("Usage: XXX.verilator infile outfile W H inputBitsPerPixel inP outputBitsPerPixel outP");
    exit(1);
  }

  VERILATORCLASS* top = new VERILATORCLASS;

  bool CLK = false;

  int W = atoi(argv[3]);
  int H = atoi(argv[4]);
  int inbpp = atoi(argv[5]);
  int inP = atoi(argv[6]);
  int outbpp = atoi(argv[7]);
  int outP = atoi(argv[8]);

  int outPackets = (W*H)/outP;
  
  for(int i=0; i<100; i++){
    CLK = !CLK;
    setValid(&(top->process_input),inbpp*inP,false);
    top->CLK = CLK;
    top->reset = true;
    top->ready_downstream = 1;
    top->eval();
  }

  FILE* infile = fopen(argv[1],"rb");
  FILE* outfile = fopen(argv[2],"wb");

  if(infile==NULL){printf("could not open input\n");}
  if(outfile==NULL){printf("could not open output\n");}

  int validcnt = 0;

  unsigned long totalCycles = 0;

  while (!Verilated::gotFinish() && validcnt<outPackets) {
    if(CLK){
      if(top->ready){
        if(feof(infile)){
          setValid(&(top->process_input),inbpp*inP,false);
        }else{
	  setData(&(top->process_input),inbpp*inP,infile);
          setValid(&(top->process_input),inbpp*inP,true);
        }
      }

      if(getValid( &(top->process_output), outbpp*outP ) ){
        validcnt++;
	getData(&(top->process_output),outbpp*outP,outfile);
      }

      totalCycles++;
      if(totalCycles>outPackets*256){
        printf("Simulation went on for way too long, giving up!\n");
        exit(1);
      }
    }

    CLK = !CLK;

    top->CLK = CLK;
    top->ready_downstream = true;
    top->reset = false;
    top->eval();
  }

  top->final();
  delete top;
}
