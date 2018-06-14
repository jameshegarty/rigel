#include <verilated.h>
#include <iostream>
#include <stdio.h>
#include VERILATORFILE
#include <queue>

#include "harness.h"
#include <sys/time.h>

double CurrentTimeInSeconds() {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return tv.tv_sec + tv.tv_usec / 1000000.0;
}

#define S0LIST 0,&top->IP_CLK,&top->IP_ARESET_N,&top->SAXI0_ARADDR,&top->SAXI0_ARVALID,&top->SAXI0_ARREADY,&top->SAXI0_AWADDR,&top->SAXI0_AWVALID,&top->SAXI0_AWREADY,&top->SAXI0_RDATA,&top->SAXI0_RVALID,&top->SAXI0_RREADY,&top->SAXI0_BRESP,&top->SAXI0_BVALID,&top->SAXI0_BREADY

#define M0READLIST 0,&top->MAXI0_ARADDR,&top->MAXI0_ARVALID,&top->MAXI0_ARREADY,&top->MAXI0_RDATA,&top->MAXI0_RVALID,&top->MAXI0_RREADY,&top->MAXI0_RRESP,&top->MAXI0_RLAST,&top->MAXI0_ARLEN,&top->MAXI0_ARSIZE,&top->MAXI0_ARBURST

#define M0WRITELIST 0,&top->MAXI0_AWADDR,&top->MAXI0_AWVALID,&top->MAXI0_AWREADY,&top->MAXI0_WDATA,&top->MAXI0_WVALID,&top->MAXI0_WREADY,&top->MAXI0_BRESP,&top->MAXI0_BVALID,&top->MAXI0_BREADY,&top->MAXI0_WSTRB,&top->MAXI0_WLAST,&top->MAXI0_AWLEN,&top->MAXI0_AWSIZE,&top->MAXI0_AWBURST

#define M1READLIST 1,&top->MAXI1_ARADDR,&top->MAXI1_ARVALID,&top->MAXI1_ARREADY,&top->MAXI1_RDATA,&top->MAXI1_RVALID,&top->MAXI1_RREADY,&top->MAXI1_RRESP,&top->MAXI1_RLAST,&top->MAXI1_ARLEN,&top->MAXI1_ARSIZE,&top->MAXI1_ARBURST

#define M1WRITELIST 1,&top->MAXI1_AWADDR,&top->MAXI1_AWVALID,&top->MAXI1_AWREADY,&top->MAXI1_WDATA,&top->MAXI1_WVALID,&top->MAXI1_WREADY,&top->MAXI1_BRESP,&top->MAXI1_BVALID,&top->MAXI1_BREADY,&top->MAXI1_WSTRB,&top->MAXI1_WLAST,&top->MAXI1_AWLEN,&top->MAXI1_AWSIZE,&top->MAXI1_AWBURST


void step(VERILATORCLASS* top){
  top->IP_CLK = 0;
  top->eval();
  top->IP_CLK = 1;
  top->eval();
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv); 

  printf("Usage: XXX.verilator simCycles memStart memEnd [--verbose] --inputs file1.raw address1 file2.raw address2 --outputs ofile1.raw address w h bitsPerPixel\n");

  int simCycles = atoi(argv[1]);
  int simCyclesSlack = simCycles/10;
  unsigned int MEMBASE = strtol(argv[2],NULL,16);
  unsigned int MEMSIZE = strtol(argv[3],NULL,16)-MEMBASE;

  std::cout << "SimCycles: " << simCycles << " SimCyclesSlack: " << simCyclesSlack << " MemBase: 0x" << std::hex << MEMBASE << std::dec << " MemSize: " << MEMSIZE << std::endl;

  bool verbose = false;
  int curArg = 4;

  if(strcmp(argv[curArg],"--verbose")==0){
    verbose = true;
    curArg++;
  }

  if(strcmp(argv[curArg],"--inputs")!=0){
    std::cout << "fourth argument should be '--inputs' but is " << argv[4] << std::endl;
  }else{
    curArg++;
  }

  int inputCount = 0;

  unsigned char* memory = (unsigned char*)malloc(MEMSIZE);
  for(int i=0; i<MEMSIZE; i+=4){ *(unsigned int*)(memory+i)=0x0df0adba; }
  
  init();
  
  while(strcmp(argv[curArg],"--outputs")!=0){
    unsigned int addr = strtol(argv[curArg+1],NULL,16);
    unsigned int addrOffset = addr-MEMBASE;

    loadFile( argv[curArg], memory, addrOffset );
    inputCount++;
    curArg+=2;
  }

  
  VERILATORCLASS* top = new VERILATORCLASS;

  bool CLK = false;

  const int ROUNDS = 2;
  for(int round=0; round<ROUNDS; round++){
    printf("ROUND %d\n",round);
    
    unsigned long cycle = 0;
    unsigned long totalCycles = simCycles+simCyclesSlack;
    
    if(verbose){printSlave(S0LIST);}
    
    for(int i=0; i<100; i++){
      CLK = !CLK;
      
      top->IP_CLK = CLK;
      top->IP_ARESET_N = false;
      
      resetSlave(S0LIST);
      
      deactivateMasterRead(M0READLIST);
      deactivateMasterWrite(M0WRITELIST);
      deactivateMasterRead(M1READLIST);
      deactivateMasterWrite(M1WRITELIST);
      
      top->eval();
    }
    
    top->IP_ARESET_N=true;
    step(top);
    if(verbose){printSlave(S0LIST);}
    
    step(top);
    if(verbose){printSlave(S0LIST);}
    
    step(top);
    if(verbose){printSlave(S0LIST);}
    
    // send start cmd
    //assert(top->SAXI0_AWREADY==1);
    top->SAXI0_AWADDR = 0xA0000000;
    top->SAXI0_AWVALID = true;
    step(top);
    if(verbose){printSlave(S0LIST);}
    bool found = checkSlaveResponse(S0LIST);
    
    assert(top->SAXI0_WREADY==1);
    top->SAXI0_WDATA = 1;
    top->SAXI0_WVALID = 1;
    step(top);
    found |= checkSlaveResponse(S0LIST);
    
    top->SAXI0_AWVALID = false;
    step(top);
    
    while(!found && !checkSlaveResponse(S0LIST)){
      std::cout << "Waiting for S0 response" << std::endl;
    }
    
    // now we're ready to service memory requests
    activateMasterRead(M0READLIST);
    activateMasterWrite(M0WRITELIST);
    activateMasterRead(M1READLIST);
    activateMasterWrite(M1WRITELIST);
    
    int lastPct = -1;
    double startSec = CurrentTimeInSeconds();
    
    while (!Verilated::gotFinish() && cycle<totalCycles ) {
      if(CLK){
        if(verbose){ std::cout << "------------------------------------ START CYCLE " << cycle <<  ", ROUND " << round << " (" << ((float)cycle/(float)(simCycles+simCyclesSlack))*100.f << "%) -----------------------" << std::endl;}
        // feed data in
        masterReadData(verbose,memory,M0READLIST);
        masterReadData(verbose,memory,M1READLIST);
        
        // it's possible the pipeline has 0 cycle delay (between read & write port). in which case, we need to eval the async stuff here.
        top->eval();
        
        if(verbose){printMasterRead(M0READLIST);}
        if(verbose){printMasterWrite(M0WRITELIST);}
        
        masterWriteData(verbose,memory,M0WRITELIST);
        masterWriteData(verbose,memory,M1WRITELIST);
        
        // get data out
        masterReadReq(verbose,MEMBASE,MEMSIZE,M0READLIST);
        masterWriteReq(verbose,MEMBASE,MEMSIZE,M0WRITELIST);
        
        masterReadReq(verbose,MEMBASE,MEMSIZE,M1READLIST);
        masterWriteReq(verbose,MEMBASE,MEMSIZE,M1WRITELIST);
        
        int pct = (cycle*100)/totalCycles;
        if(pct>lastPct){
          double t = CurrentTimeInSeconds() - startSec;
          setlocale(LC_NUMERIC,"");
          printf("Sim %d %% complete! (%'d/%'d cycles) (%f sec elapsed, %f to go) (%d bytes read, %d bytes written)\n",pct,cycle,totalCycles,t,t*((float)(100-pct))/((float)(pct)),bytesRead(),bytesWritten());
          lastPct = pct;
        }
        
        cycle++;
      }
      
      CLK = !CLK;
      
      top->IP_CLK = CLK;
      top->IP_ARESET_N = true;
      top->eval();
    }
    
    if(round==ROUNDS-1){
      top->final();
      delete top;
    }
    
    printf("Executed Cycles: %d\n", (int)cycle);
    
    curArg++; // for "--outputs"
    unsigned int outputCount = 0;
    while(curArg<argc){
      unsigned int addr = strtol(argv[curArg+1],NULL,16);
      unsigned int addrOffset = addr-MEMBASE;
      
      unsigned int w = atoi(argv[curArg+2]);
      unsigned int h = atoi(argv[curArg+3]);
      unsigned int bitsPerPixel = atoi(argv[curArg+4]);
      
      if( bitsPerPixel%8!=0 ){
        std::cout << "Error, bits per pixel not byte aligned!" << std::endl;
        exit(1);
      }
      
      unsigned int bytes = w*h*(bitsPerPixel/8);
      
      std::string outFilename = std::string(argv[curArg])+std::string(".verilatorSOC.raw");
      
      saveFile(outFilename.c_str(), memory, addrOffset, bytes);
      
      curArg+=5;
      outputCount++;
    }
    
    bool errored = checkPorts();
    
    if(errored){
      exit(1);
    }
  } // rounds
}
