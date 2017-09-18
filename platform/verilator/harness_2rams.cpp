#include <verilated.h>
#include <iostream>
#include <stdio.h>
#include <queue>
#include "harness.h"
#include VERILATORFILE

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv); 

  if(argc!=13 && argc!=14){
    printf("Usage: XXX.verilator infile outfile inW inH inputBitsPerPixel inP outW outH outputBitsPerPixel outP tapBits tapValue [simCycles]");
    exit(1);
  }

  printf("RAMBITS %d %s\n",RAMBITS,RAMFILE);

  if(RAMBITS%8!=0){
    printf("RAMBITS not byte aligned!\n");
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
    setValid(&(top->process_input),inbpp*inP,false);
    setValid(&(top->process_input),inbpp*inP+RAMBITS+1,false);
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

  const int ADDR_DELAY = 10;
  std::queue<int> addrqueue;
  long RAMFILE_size;
  unsigned char* dataBuffer = (unsigned char*)(readFile(RAMFILE,&RAMFILE_size));

  printf("STARTSIM\n");
  
  while (!Verilated::gotFinish() && (validcnt<outPackets || (simCycles!=0 && totalCycles<simCycles)) ) {
    if(CLK){
      if( top->ready & (unsigned int)(1) ){
        if(validInCnt>=inPackets){
          setValid(&(top->process_input),inbpp*inP+tapBits,false);
        }else{
          setData(&(top->process_input),inbpp*inP,infile);
          setDataBuf(&(top->process_input),tapBits,inbpp*inP,tapValue);
          setValid(&(top->process_input),inbpp*inP+tapBits,true);
          validInCnt++;
        }
      }


      bool ramReadValid = addrqueue.size()>=ADDR_DELAY && addrqueue.front()!=-1;
      setValid( &(top->process_input), inbpp*inP+RAMBITS+1, ramReadValid );
               
      if( top->ready & (unsigned int)(2) ){

        if(ramReadValid){
          unsigned int addr = addrqueue.front();
          addrqueue.pop();
          
          if(addr>=0){
            unsigned int raddr = (addr*RAMBITS)/8;

            if(raddr>=RAMFILE_size){
              printf("READ BEYOND END OF MEMORY!!\n");
              exit(1);
            }

            setDataBuf( &(top->process_input), RAMBITS, inbpp*inP+1, &dataBuffer[raddr] );
          }
        }else if(addrqueue.size()>=ADDR_DELAY){
          assert(addrqueue.front()==-1);
          addrqueue.pop();
        }
      }
      
      // it's possible the pipeline has 0 cycle delay. in which case, we need to eval the async stuff here.
      top->eval();
      
      if(getValid( &(top->process_output), outbpp*outP ) ){
        validcnt++;
        getData(&(top->process_output),outbpp*outP,outfile);
      }

      // ready to accept addrs
      //printf("ADDR QUEUE SIZE %d\n",addrqueue.size());
      bool addrReady = addrqueue.size()<ADDR_DELAY;
      if(addrReady){
        top->ready_downstream |= (unsigned int)(2);
      }else{
        top->ready_downstream &= (unsigned int)(1);
      }

      if(getValid( &(top->process_output), outbpp*outP+32+1 ) && addrReady ){
        //printf("MEM ADDR VALID %d %d\n",outbpp,outP);

        unsigned int addr = getUintData( &(top->process_output), outbpp*outP+1 );
        //printf("READ ADDR %d\n",addr);

        addrqueue.push(addr);
        //printf("ADDRQa %d\n",addrqueue.size());
              
      }else if(addrReady){
        //printf("MEM ADDR INVALID %d %d\n",outbpp,outP);
        addrqueue.push(-1);
        //printf("ADDRQ %d\n",addrqueue.size());

      }
      
              
      totalCycles++;
      if(totalCycles>outPackets*256){
        printf("Simulation went on for way too long, giving up! cycles: %d, expectedOutputPackets %d validOutputsSeen %d\n",(unsigned int)totalCycles,outPackets,validcnt);
        exit(1);
      }
    }

    CLK = !CLK;

    top->CLK = CLK;

    // ready to accept data
    top->ready_downstream |= (unsigned int)(1);

    
    top->reset = false;
    top->eval();
  }

  top->final();
  delete top;
}
