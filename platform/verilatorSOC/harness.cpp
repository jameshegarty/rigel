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

#define S0LIST 0,&top->IP_CLK,&top->IP_ARESET_N,&top->SAXI0_ARADDR,&top->SAXI0_ARVALID,&top->SAXI0_ARREADY,&top->SAXI0_AWADDR,&top->SAXI0_AWVALID,&top->SAXI0_AWREADY,&top->SAXI0_RDATA,&top->SAXI0_RVALID,&top->SAXI0_RREADY,&top->SAXI0_BRESP,&top->SAXI0_BVALID,&top->SAXI0_BREADY,&top->SAXI0_RRESP,&top->SAXI0_WVALID,&top->SAXI0_WREADY

#define M0READ_SLAVEOUT &top->MAXI0_ARREADY,&top->MAXI0_RDATA,&top->MAXI0_RVALID,&top->MAXI0_RRESP,&top->MAXI0_RLAST
#define M0READ_SLAVEIN &top->MAXI0_ARADDR,&top->MAXI0_ARVALID,&top->MAXI0_RREADY,&top->MAXI0_ARLEN,&top->MAXI0_ARSIZE,&top->MAXI0_ARBURST

#define M0WRITE_SLAVEOUT &top->MAXI0_AWREADY,&top->MAXI0_WREADY,&top->MAXI0_BRESP,&top->MAXI0_BVALID
#define M0WRITE_SLAVEIN &top->MAXI0_AWADDR,&top->MAXI0_AWVALID,&top->MAXI0_WDATA,&top->MAXI0_WVALID,&top->MAXI0_BREADY,&top->MAXI0_WSTRB,&top->MAXI0_WLAST,&top->MAXI0_AWLEN,&top->MAXI0_AWSIZE,&top->MAXI0_AWBURST

#define M1READ_SLAVEOUT &top->MAXI1_ARREADY,&top->MAXI1_RDATA,&top->MAXI1_RVALID,&top->MAXI1_RRESP,&top->MAXI1_RLAST
#define M1READ_SLAVEIN &top->MAXI1_ARADDR,&top->MAXI1_ARVALID,&top->MAXI1_RREADY,&top->MAXI1_ARLEN,&top->MAXI1_ARSIZE,&top->MAXI1_ARBURST

#define M1WRITE_SLAVEOUT &top->MAXI1_AWREADY,&top->MAXI1_WREADY,&top->MAXI1_BRESP,&top->MAXI1_BVALID
#define M1WRITE_SLAVEIN &top->MAXI1_AWADDR,&top->MAXI1_AWVALID,&top->MAXI1_WDATA,&top->MAXI1_WVALID,&top->MAXI1_BREADY,&top->MAXI1_WSTRB,&top->MAXI1_WLAST,&top->MAXI1_AWLEN,&top->MAXI1_AWSIZE,&top->MAXI1_AWBURST


void step(VERILATORCLASS* top){
  top->IP_CLK = 0;
  top->eval();
  top->IP_CLK = 1;
  top->eval();
}

void setReg(VERILATORCLASS* top, bool verbose, unsigned int addr, unsigned int data){

  bool srVerbose = false; // verbose just for this fn
  
  //////////////////////////////////////////////////////////////
  step(top);
  if(srVerbose || verbose){printSlave(S0LIST);}
  
  //////////////////////////////////////////////////////////////
  step(top);
  if(srVerbose || verbose){printSlave(S0LIST);}
  
  //////////////////////////////////////////////////////////////
  step(top);
  if(srVerbose || verbose){printSlave(S0LIST);}
  
  // send start cmd
  //assert(top->SAXI0_AWREADY==1);
  top->SAXI0_AWADDR = addr;
  top->SAXI0_AWVALID = true;
  
  //////////////////////////////////////////////////////////////
  step(top);
  if(srVerbose || verbose){printSlave(S0LIST);}
  bool found = checkSlaveWriteResponse(S0LIST);

  int i=0;
  while(top->SAXI0_WREADY!=1){
    step(top);
    if(srVerbose || verbose){ printf("Waiting for ready\n"); printSlave(S0LIST); }
    if(i>5){printf("timeout waiting for slave ready\n");exit(1);}
  }
  
  top->SAXI0_WDATA = data;
  top->SAXI0_WVALID = 1;
  
  //////////////////////////////////////////////////////////////
  step(top);
  found |= checkSlaveWriteResponse(S0LIST);
  
  top->SAXI0_AWVALID = false;
  
  //////////////////////////////////////////////////////////////
  step(top);

  i = 0;
  while(!found && !checkSlaveWriteResponse(S0LIST)){
    std::cout << "Waiting for S0 response" << std::endl;
    if(i>5){printf("timeout waiting for s0 response\n"); exit(1);}
    i++;
  }
}

void readReg(VERILATORCLASS* top, bool verbose, unsigned int addr, unsigned int* data){
  printf("READREG\n");
  top->SAXI0_ARADDR = addr;
  top->SAXI0_ARVALID = true;
  top->SAXI0_RREADY = true;
  
  step(top);

  printf("HERE\n");
  while(top->SAXI0_RVALID!=1){
    step(top);
    printf("Waiting for reg read\n");
  }

  printf("READREG DAT %d\n",top->SAXI0_RDATA);
  *data = top->SAXI0_RDATA;
  top->SAXI0_ARVALID = false;

  step(top);
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

  unsigned char* memory = (unsigned char*)malloc(MEMSIZE);
  for(int i=0; i<MEMSIZE; i+=4){ *(unsigned int*)(memory+i)=0x0df0adba; }
  
  init();

  // load inputs
  int inputCount = 0;
  while(strcmp(argv[curArg],"--registers")!=0){
    unsigned int addr = strtol(argv[curArg+1],NULL,16);
    unsigned int addrOffset = addr-MEMBASE;

    loadFile( argv[curArg], memory, addrOffset );
    inputCount++;
    curArg+=2;
  }

  SlaveState slaveState0;
  SlaveState slaveState1;
  initSlaveState(&slaveState0);
  initSlaveState(&slaveState1);
    
  VERILATORCLASS* top = new VERILATORCLASS;

  bool CLK = false;

  const int ROUNDS = 2;
  for(int round=0; round<ROUNDS; round++){
    printf("ROUND %d\n",round);
    
    unsigned long cycle = 0;
    unsigned long totalCycles = simCycles+simCyclesSlack;
    
    if(verbose){printSlave(S0LIST);}

    if(round==0){
      for(int i=0; i<100; i++){
        CLK = !CLK;
        
        top->IP_CLK = CLK;
        top->IP_ARESET_N = false;
        
        resetSlave(S0LIST);
        
        deactivateMasterRead( M0READ_SLAVEOUT );
        deactivateMasterWrite( M0WRITE_SLAVEOUT );
        deactivateMasterRead( M1READ_SLAVEOUT );
        deactivateMasterWrite( M1WRITE_SLAVEOUT );
        
        top->eval();
      }

      top->IP_ARESET_N=true;

      curArg++; // for "--registers"
      while(strcmp(argv[curArg],"--outputs")!=0){
        printf("PARSE ARG %s %s\n",argv[curArg],argv[curArg+1]);
        unsigned int addr = strtol(argv[curArg],NULL,16);
        int hexlen = strlen(argv[curArg+1]);
        if(hexlen%2!=0){
          printf("NON byte size?");
          exit(1);
        }
        int bytes = hexlen/2;
        printf("Set Register %x withNBytes %d\n",addr,bytes);

        //unsigned int* data = (unsigned int*)argv[curArg+1];
        char tmp[9]="";

        int numints = bytes/4;
        if(numints<=0){numints=1;}
        
        for(int i=0; i<numints; i++){
          int numhex = 8;
          if(bytes<4){numhex=bytes*2;}
          for(int j=0; j<numhex; j++){
            tmp[j] = argv[curArg+1][i*numhex+j];
          }

          printf("STR %s\n",tmp);
          unsigned long data = strtoul(tmp,NULL,16);
          printf("try to Set Reg addr:%x with data:%x\n",addr,data);
          setReg( top, verbose, addr+i*4, data);
        }
        
        curArg+=2;
      }
    }else{
      resetSlave(S0LIST);
    }
    
    
    setReg(top,verbose,0xA0000000+4,0); // clear done bit
    setReg(top,verbose,0xA0000000,1); // set start bit
    
    // now we're ready to service memory requests
    activateMasterRead( M0READ_SLAVEOUT );
    activateMasterWrite( M0WRITE_SLAVEOUT );
    activateMasterRead( M1READ_SLAVEOUT );
    activateMasterWrite( M1WRITE_SLAVEOUT );
    
    int lastPct = -1;
    double startSec = CurrentTimeInSeconds();

    bool doneBitSet = false;
    unsigned int cyclesToDoneSignal = -1;
    int cooldownCycles = 1000; // run for a few extra cycles after the done bit is set, to make sure nothing crazy happens
    if(totalCycles/10<cooldownCycles){cooldownCycles=totalCycles/10;}
    bool cooldownPrinted = false;
    
    while (!Verilated::gotFinish() && (doneBitSet==false || cooldownCycles>0 || cycle<totalCycles)) {
      if(CLK){
        if(verbose){ std::cout << "------------------------------------ START CYCLE " << cycle <<  ", ROUND " << round << " (" << ((float)cycle/(float)(simCycles+simCyclesSlack))*100.f << "%) -----------------------" << std::endl;}
        // feed data in
        masterReadDataDriveOutputs( verbose, memory, 0, M0READ_SLAVEOUT );
        masterReadDataLatchFlops( verbose, memory, 0, M0READ_SLAVEIN );
        masterReadDataDriveOutputs( verbose, memory, 1, M1READ_SLAVEOUT );
        masterReadDataLatchFlops( verbose, memory, 1, M1READ_SLAVEIN );
        
        // it's possible the pipeline has 0 cycle delay (between read & write port). in which case, we need to eval the async stuff here.
        top->eval();
        
        if(verbose){printMasterRead( 0, M0READ_SLAVEIN, M0READ_SLAVEOUT );}
        if(verbose){printMasterWrite( 0, M0WRITE_SLAVEIN, M0WRITE_SLAVEOUT );}
        
        masterWriteDataDriveOutputs( verbose, memory, &slaveState0, 0, M0WRITE_SLAVEOUT );
        masterWriteDataLatchFlops( verbose, memory, &slaveState0, 0, M0WRITE_SLAVEIN );
        masterWriteDataDriveOutputs( verbose, memory, &slaveState1, 1, M1WRITE_SLAVEOUT );
        masterWriteDataLatchFlops( verbose, memory, &slaveState1, 1, M1WRITE_SLAVEIN );
        
        // get data out
        masterReadReqDriveOutputs( verbose, MEMBASE, MEMSIZE, 0, M0READ_SLAVEOUT );
        masterReadReqLatchFlops( verbose, MEMBASE, MEMSIZE, 0, M0READ_SLAVEIN );
        masterWriteReqDriveOutputs( verbose, MEMBASE, MEMSIZE, 0, M0WRITE_SLAVEOUT );
        masterWriteReqLatchFlops( verbose, MEMBASE, MEMSIZE, 0, M0WRITE_SLAVEIN );
        
        masterReadReqDriveOutputs( verbose, MEMBASE, MEMSIZE, 1, M1READ_SLAVEOUT );
        masterReadReqLatchFlops( verbose, MEMBASE, MEMSIZE, 1, M1READ_SLAVEIN );
        masterWriteReqDriveOutputs( verbose, MEMBASE, MEMSIZE, 1, M1WRITE_SLAVEOUT );
        masterWriteReqLatchFlops( verbose, MEMBASE, MEMSIZE, 1, M1WRITE_SLAVEIN );

        if(cycle%100==0){
          slaveReadReq(0xA0000000+4,S0LIST);
        }

        unsigned int db;
        if( checkSlaveReadResponse(S0LIST,&db) ){
          if(db==1){
            if(doneBitSet==false){
              cyclesToDoneSignal=cycle;
            }
            
            doneBitSet=true;
          }else{
            doneBitSet=false;
          }
        }

        if(doneBitSet && cooldownCycles>0){
          if(!cooldownPrinted){
            printf("Start Cooldown\n");
            cooldownPrinted = true;
          }
          
          cooldownCycles--;
        }
        
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
    
    printf("Executed Cycles: %d, Cycles to Done: %d\n", (int)cycle, cyclesToDoneSignal);
    
    bool errored = checkPorts();

    if(doneBitSet==false){
      printf("Error: done bit not set at end of time?\n");
      errored = true;
    }
    
    if(errored){
      exit(1);
    }
  } // rounds

  printf("CUR %s\n",argv[curArg-1]);
  printf("CUR %s\n",argv[curArg]);
  
  curArg++; // for "--outputs"
  unsigned int outputCount = 0;
  //
  char* outfile;
  while(strcmp(argv[curArg],"--registersOut")!=0){
    printf("OUTPUT %d %s\n",curArg,argv[curArg]);
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
    outfile = argv[curArg];
    
    saveFile(outFilename.c_str(), memory, addrOffset, bytes);
    
    curArg+=5;
    outputCount++;
  }

  std::string regFilename = std::string(outfile)+std::string(".verilatorSOC.regout.lua");
  FILE* regFile = fopen(regFilename.c_str(),"w");
  fprintf(regFile,"return {");
  
  curArg++; // for '--registersOut'
  bool first = true;
  while(curArg<argc){
    unsigned int regOut = 0;
    unsigned int addr = strtol(argv[curArg+1],NULL,16);
    readReg(top,false,addr,&regOut);
    printf("READREG %s %d\n",argv[curArg],regOut);
    if(!first){fprintf(regFile,",");}
    first=false;
    fprintf(regFile,"%s=%d",argv[curArg],regOut);
    curArg+=2;
  }
  fprintf(regFile,"}");
  fclose(regFile);
  
  top->final();
  delete top;
}
