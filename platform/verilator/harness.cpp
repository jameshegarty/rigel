#include <verilated.h>
#include <iostream>
#include <stdio.h>
#include "harness.h"
#include VERILATORFILE

int intCeil(int N, int D){
  int w = N/D;
  int r = N%D;
  assert( w*D+r == N ); // I think this is always true...
  return w + (r>0?1:0);
}

bool calcThrottle( bool isInput, int N, int D, int delay, int cycles ){
  //float vLast = ceilf( (float(N)/float(D))*(float(cycles)-float(delay)) );
  int vLastN = N*(cycles-delay);
  int vLastD = D;
  if(vLastN<0.f){vLastN=0;}
  int viLast = intCeil(vLastN,vLastD);
  
  //float vf = (float(N)/float(D))*(float(cycles)-float(delay)+1.f);
  //float v = ceilf( vf );
  //if(v<0.f){v=0.f;}
  int vN = N*(cycles-delay+1);
  int vD = D;
  if(vN<0.f){vN=0;}
  int vi = intCeil(vN,vD);

  
  //  unsigned int viLast = vLast;
  //  unsigned int vi = v;

  bool throttle = (vi != viLast);
  
  if( isInput ){
  int vLastN = N*(cycles-delay);
  int vlastD = D;
  if(vLastN<0.f){vLastN=0;}
  int viLast = intCeil(vLastN,vLastD);
  //printf("Calc input %d/%d cyc:%3u expected:%3f expectedInt:%3d expectedFloat:%f throttle:%d\n",N,D,cycles,v,vi,vf,throttle?1:0);
  //printf("Calc input %d/%d cyc:%3u expected:%3d throttle:%d\n",N,D,cycles,vi,throttle?1:0);
  }else{
    //        printf("Calc output %d/%d cyc:%lu expected:%f expectedInt:%d expectedFloat:%f delay:%d\n",N,D,cycles,v,vi,vf,delay);
  }
  
  return throttle;
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv); 

  if(argc!=19 && argc!=20){
    printf("Usage: XXX.verilator infile outfile inW inH inputBitsPerPixel inP inN inD outW outH outputBitsPerPixel outP outN outD delay MONITOR_FIFOS tapBits tapValue [simCycles]");
    exit(1);
  }

  VERILATORCLASS* top = new VERILATORCLASS;

  bool CLK = false;

  unsigned int inW = atoi(argv[3]);
  unsigned int inH = atoi(argv[4]);
  unsigned int inbpp = atoi(argv[5]);
  unsigned int inP = atoi(argv[6]);
  unsigned int inN = atoi(argv[7]);
  unsigned int inD = atoi(argv[8]);
      
  unsigned int outW = atoi(argv[9]);
  unsigned int outH = atoi(argv[10]);
  unsigned int outbpp = atoi(argv[11]);
  unsigned int outP = atoi(argv[12]);
  unsigned int outN= atoi(argv[13]);
  unsigned int outD = atoi(argv[14]);

  unsigned int delay = atoi(argv[15]);

  char* MONITOR_FIFOS_STR = argv[16];
  bool MONITOR_FIFOS = true;
  if( strcmp(MONITOR_FIFOS_STR,"false")==0 ){MONITOR_FIFOS=false;}
  
  int tapBits = atoi(argv[17]);

  unsigned char* tapValue = (unsigned char*)malloc(tapBits/8);
  char* pos = argv[18];

  for(int count = 0; count < tapBits/8; count++) {
    sscanf(pos, "%2hhx", &tapValue[(tapBits/8)-count-1]);
    pos += 2;
  }

  int simCycles = 0;
  if(argc==20){simCycles = atoi(argv[19]);}
  
  unsigned int inPackets = (inW*inH)/inP;
  unsigned int outPackets = (outW*outH)/outP;
  
  for(int i=0; i<100; i++){
    CLK = !CLK;

    setValid(&(top->process_input),inbpp*inP,false);

    top->CLK = CLK;
#if STATEFUL==true
    top->reset = true;
#endif
    top->ready_downstream = 1;

#if TAPBITS>0
    setDataBuf(&(top->taps_taps_output),tapBits,0,tapValue);
#endif
    
    top->eval();
  }

  FILE* infile = fopen(argv[1],"rb");
  FILE* outfile = fopen(argv[2],"wb");

  if(infile==NULL){printf("could not open input '%s'\n", argv[1]);}
  if(outfile==NULL){printf("could not open output '%s'\n", argv[2]);}

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

  top->CLK = false;
  top->eval();
  top->CLK = true;
  top->eval();

  bool ready = top->ready;

  printf("Start Sim\n");

  //int kill = -1;
  bool kill = false;
  while (!Verilated::gotFinish() && (validcnt<outPackets || (simCycles!=0 && totalCycles<simCycles)) ) {
    // posedge just occured, registers from last cycle were latched

    bool iThrottle = calcThrottle( true, inN, inD, 0, totalCycles );
    bool oThrottle = calcThrottle( false, outN, outD, delay, totalCycles );

    //    printf("SIM cyc %d oThrottle %d\n",totalCycles,oThrottle);
    // set all inputs. DO NOT READ OUTPUTS DIRECTLY. Imagine these inputs come from registers, which should happen _after_ the posedge.
#if STATEFUL==true
    top->reset = false;
#endif
    //    if( MONITOR_FIFOS ){
    //      top->ready_downstream = oThrottle || (validcnt==0);
    //    }else{
      top->ready_downstream = 1;
      //    }
    
    if(ready){
      // only send tokens in when we expect them
      if( validInCnt>=inPackets || (iThrottle==false && MONITOR_FIFOS)){ // either we're done, or throttled
      //if( validInCnt>=inPackets){
        setValid(&(top->process_input),inbpp*inP,false);
      }else{
        setData(&(top->process_input),inbpp*inP,infile);
        setValid(&(top->process_input),inbpp*inP,true);
        validInCnt++;
      }
    }

    if( iThrottle && top->ready==false && MONITOR_FIFOS ){
      printf("Error: DUT input ready wasn't as expected in cycle %lu. expected:%d ready:%d rate:%d/%d delay:%d\n", totalCycles, iThrottle,top->ready,inN, inD, delay);
      kill = true;
    }

    top->eval();

    // flip to negedge.
    top->CLK = false;
    top->eval();

    // read outputs
    bool outValid = getValid( &(top->process_output), outbpp*outP );

    if( outValid!=oThrottle && MONITOR_FIFOS ){
      printf("Error: DUT output valid was not as expected! expected:%d valid:%d in cycle:%lu delay:%d validCount:%d/%d\n", oThrottle, outValid, totalCycles, delay, validcnt, outPackets );
      kill = true;
    }
    
    if( outValid ){
      validcnt++;
      getData(&(top->process_output),outbpp*outP,outfile);
    }

    ready = top->ready;

    // activate posedge
    top->CLK = true;
    top->eval();
    
    totalCycles++;
    float expectedOutputsAtThisPoint = (float)totalCycles*((float)outN/(float)outD);
    int seenRef = validcnt*2+200000;
    if( expectedOutputsAtThisPoint > seenRef ){
      printf("Simulation went on for way too long, giving up! cycles: %d, expectedOutputPackets %f validOutputsSeen %d inputsSentIn:%d seenref:%d\n", (unsigned int)totalCycles, expectedOutputsAtThisPoint, validcnt, validInCnt, seenRef );
      exit(1);
    }
  }

  printf("Verilator Cycles: %d\n", (int)totalCycles);

  if(kill){
    exit(1);
  }
  
  // dumb hack: put it back into reset, to signal fifos to print errors on being too large
  CLK = true;
  for(int i=0; i<2; i++){
    CLK = !CLK;
    top->CLK = CLK;
    
#if STATEFUL==true
    top->reset = true;
#endif
    top->eval();

    if(Verilated::gotFinish()){
      exit(1);
    }
  }
    
  top->final();
  delete top;

  std::string cycfile = argv[2];
  cycfile = cycfile.substr(0,cycfile.size()-3)+std::string("cycles.txt");
  // write cycles to file
  FILE *f = fopen(cycfile.c_str(), "w");
  if (f == NULL){
    printf("Error opening file '%s'!\n",cycfile.c_str());
    exit(1);
  }
  fprintf(f, "%d", (int)totalCycles);
  fclose(f);
}
