#include <verilated.h>
#include <iostream>
#include VERILATORFILE

/*unsigned int divCeil(unsigned int a, unsigned int b){
  float aa = a;
  float bb = b;
  return (unsigned int)(ceil(aa/bb));
  }*/

unsigned int bitsToBytes(unsigned int bits){
  if(bits<=8){
    return 1;
  }else if(bits<=16){
    return 2;
  }else if(bits<=32){
    return 4;
  }else if(bits<=64){
    return 8;
  }else{
    assert(false);
  }
}

template<typename T>
void setValid(T* signal, unsigned int databits, bool valid){
  // for this verilator data type, we should have < 16 bits
  assert(databits<=sizeof(T)*8);

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

template<typename T>
bool getValid(T* signal, unsigned int databits){
  // for this verilator data type, we should have < 16 bits
  assert(databits<=sizeof(T)*8);
  return (*signal & ((T)(1)<<databits)) != 0;
}

template<int N>
bool getValid(WData (*signal)[N], unsigned int databits){
  int idx = databits/32; // floor
  return ( (*signal)[idx] & (1<<(databits-idx*32)) ) != 0;
}
    
template<typename T>
void setData(T* signal, unsigned int databits, FILE* file){
  // for this verilator data type, we should have < 16 bits
  assert(databits<=sizeof(T)*8);

  int readBytes = bitsToBytes(databits);

  *signal = 0;
  for(int i=0; i<readBytes; i++){
    // assume little endian (x86 style) in the file
    unsigned long inp = fgetc(file);
    *signal |= (inp << i*8);
  }
}

template<int N>
void setData(WData (*signal)[N], unsigned int databits, FILE* file){
  assert(databits==64);

  for(int j=0; j<2; j++){
    (*signal)[j]=0;
    for(int i=0; i<4; i++){
      unsigned long inp = fgetc(file);
      assert(inp!=EOF);
      (*signal)[j] |= (inp << i*8);
    }
  }
}


template<typename T>
void getData(T* signal, unsigned int databits, FILE* file){
  // for this verilator data type, we should have < 16 bits
  assert(databits<=sizeof(T)*8);

  int readBytes = bitsToBytes(databits);

  T mask = ((T)1 << databits)-1;
  if(databits==sizeof(T)*8){ mask = ~ (T)(0); }

  for(int i=0; i<readBytes; i++){
    // verilator has little endian (x86 style) behavior
    unsigned char ot = (*signal) >> i*8;
    unsigned char otm = mask >> i*8;
    fputc(ot & otm,file);
  }
}

template<int N>
void getData( WData (*signal)[N], unsigned int databits, FILE* file){
  assert(databits==64);
    
  for(int j=0; j<2; j++){
    for(int i=0; i<4; i++){
      unsigned char ot = (*signal)[j] >> (i*8);
      fputc(ot,file);
    }
  }
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv); 

  if(argc!=11){
    printf("Usage: XXX.verilator infile outfile inW inH inputBitsPerPixel inP outW outH outputBitsPerPixel outP");
    exit(1);
  }

  VERILATORCLASS* top = new VERILATORCLASS;

  bool CLK = false;

  int inW = atoi(argv[3]);
  int inH = atoi(argv[4]);
  int inbpp = atoi(argv[5]);
  int inP = atoi(argv[6]);

  int outW = atoi(argv[7]);
  int outH = atoi(argv[8]);
  int outbpp = atoi(argv[9]);
  int outP = atoi(argv[10]);

  unsigned int inPackets = (inW*inH)/inP;
  unsigned int outPackets = (outW*outH)/outP;
  
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

  fseek(infile, 0L, SEEK_END);
  unsigned long insize = ftell(infile);
  fseek(infile, 0L, SEEK_SET);
  unsigned int expectedFileSize = inW*inH*bitsToBytes(inbpp);
  if(insize!= expectedFileSize){
    printf("Error, input file is incorrect size! expected %d (W:%d H:%d bitsPerPixel:%d), but is %d\n", expectedFileSize,inW,inH,inbpp,(unsigned int)insize);
    exit(1);
  }
  
  int validcnt = 0;

  unsigned long totalCycles = 0;

  unsigned int validInCnt = 0;

  // NOTE: you'd think we could check for overflows (too many output packets), but actually we can't
  // some of our modules start producing data immediately for the next frame, which is valid behavior (ie pad)
  
  while (!Verilated::gotFinish() && validcnt<outPackets ) {
    if(CLK){
      if(top->ready){
        if(validInCnt>=inPackets){
          setValid(&(top->process_input),inbpp*inP,false);
        }else{
	  setData(&(top->process_input),inbpp*inP,infile);
          setValid(&(top->process_input),inbpp*inP,true);
          validInCnt++;
        }
      }

      if(getValid( &(top->process_output), outbpp*outP ) ){
        validcnt++;
	getData(&(top->process_output),outbpp*outP,outfile);
      }

      totalCycles++;
      if(totalCycles>outPackets*256){
        printf("Simulation went on for way too long, giving up! cycles: %d, expectedOutputPackets %d\n",(unsigned int)totalCycles,outPackets);
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
