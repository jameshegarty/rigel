#include <verilated.h>
#include <iostream>
#include <stdio.h>
#include "harness.h"
#include VERILATORFILE

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv); 

  if(argc!=13 && argc!=14){
    printf("Usage: XXX.verilator infile outfile inW inH inputBitsPerPixel inP outW outH outputBitsPerPixel outP tapBits tapValue [simCycles]");
    exit(1);
  }

  VERILATORCLASS* top = new VERILATORCLASS;

  bool CLK = false;

  unsigned int inW = atoi(argv[3]);
  unsigned int inH = atoi(argv[4]);
  unsigned int inbpp = atoi(argv[5]);
  unsigned int inP = atoi(argv[6]);

  unsigned int outW = atoi(argv[7]);
  unsigned int outH = atoi(argv[8]);
  unsigned int outbpp = atoi(argv[9]);
  unsigned int outP = atoi(argv[10]);

  int tapBits = atoi(argv[11]);

  unsigned char* tapValue = (unsigned char*)malloc(tapBits/8);
  char* pos = argv[12];

  for(int count = 0; count < tapBits/8; count++) {
    sscanf(pos, "%2hhx", &tapValue[(tapBits/8)-count-1]);
    pos += 2;
  }

  int simCycles = 0;
  if(argc==14){simCycles = atoi(argv[13]);}
  
  unsigned int inPackets = (inW*inH)/inP;
  unsigned int outPackets = (outW*outH)/outP;
  
  for(int i=0; i<100; i++){
    CLK = !CLK;

#if INBPP>0
    setValid(&(top->process_input),inbpp*inP,false);
#endif

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
  
  while (!Verilated::gotFinish() && (validcnt<outPackets || (simCycles!=0 && totalCycles<simCycles)) ) {
    if(CLK){
#if INBPP>0
      if(top->ready){
        if(validInCnt>=inPackets){
          setValid(&(top->process_input),inbpp*inP+tapBits,false);
        }else{
          setData(&(top->process_input),inbpp*inP,infile);
          setDataBuf(&(top->process_input),tapBits,inbpp*inP,tapValue);
          setValid(&(top->process_input),inbpp*inP+tapBits,true);
          validInCnt++;
        }
      }
#endif
      
      // it's possible the pipeline has 0 cycle delay. in which case, we need to eval the async stuff here.
      top->eval();
      
      if(getValid( &(top->process_output), outbpp*outP ) ){
        validcnt++;
        getData(&(top->process_output),outbpp*outP,outfile);
      }
      
      totalCycles++;
      if(totalCycles>outPackets*256){
        printf("Simulation went on for way too long, giving up! cycles: %d, expectedOutputPackets %d validOutputsSeen %d\n",(unsigned int)totalCycles,outPackets,validcnt);
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

  printf("Cycles: %d\n", (int)totalCycles);
}
