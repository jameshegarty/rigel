#include <verilated.h>
#include <iostream>
#include <stdio.h>
#include VERILATORFILE
#include <queue>

typedef struct{unsigned int addr; unsigned int burst;} Transaction;

const unsigned int MEMBASE = 0x30008000;
unsigned int MEMSIZE = 8192*2;
unsigned char* memory;

std::queue<Transaction> readQ;
std::queue<Transaction> writeQ;

#define S0LIST top->IP_CLK,top->IP_ARESET_N,top->SAXI0_ARADDR,top->SAXI0_ARVALID,top->SAXI0_ARREADY,top->SAXI0_AWADDR,top->SAXI0_AWVALID,top->SAXI0_AWREADY,top->SAXI0_RDATA,top->SAXI0_RVALID,top->SAXI0_RREADY

#define M0LIST 0,top->IP_CLK,top->IP_ARESET_N,top->MAXI0_ARADDR,top->MAXI0_ARVALID,top->MAXI0_ARREADY,top->MAXI0_RDATA,top->MAXI0_RVALID,top->MAXI0_RREADY

void printSlave(
  unsigned char& IP_CLK,
  unsigned char& IP_ARESET_N,
  unsigned int& ARADDR,
  unsigned char& ARVALID,
  unsigned char& ARREADY,
  unsigned int& AWADDR,
  unsigned char& AWVALID,
  unsigned char& AWREADY,
  unsigned int& RDATA,
  unsigned char& RVALID,
  unsigned char& RREADY){

  std::cout << "----------------------" << std::endl;
  std::cout << "IP_CLK(in): " << (int)IP_CLK << std::endl;
  std::cout << "IP_ARESET_N(in): " << (int)IP_ARESET_N << std::endl;
  std::cout << "S_ARADDR(in): " << ARADDR << std::endl;
  std::cout << "S_ARVALID(in): " << (int)ARVALID << std::endl;
  std::cout << "S_ARREADY(out): " << (int)ARREADY << std::endl;
  std::cout << "S_AWADDR(in): " << AWADDR << "/" << std::hex << AWADDR  << std::dec<< std::endl;
  std::cout << "S_AWVALID(in): " << (int)AWVALID << std::endl;
  std::cout << "S_AWREADY(out): " << (int)AWREADY << std::endl;
  std::cout << "S_RDATA(out): " << RDATA << std::endl;
  std::cout << "S_RVALID(out): " << (int)RVALID << std::endl;
  std::cout << "S_RREADY(in): " << (int)RREADY << std::endl;
}

void printMasterRead(
  int id,
  unsigned char& IP_CLK,
  unsigned char& IP_ARESET_N,
  unsigned int& ARADDR,
  unsigned char& ARVALID,
  unsigned char& ARREADY,
  unsigned long& RDATA,
  unsigned char& RVALID,
  unsigned char& RREADY){

  std::cout << "----------------------" << std::endl;
  std::cout << "IP_CLK(in): " << (int)IP_CLK << std::endl;
  std::cout << "IP_ARESET_N(in): " << (int)IP_ARESET_N << std::endl;
  std::cout << "M" << id << "_ARADDR(out): " << ARADDR << "/" << std::hex << ARADDR  << std::dec<< std::endl;
  std::cout << "M" << id << "_ARVALID(out): " << (int)ARVALID << std::endl;
  std::cout << "M" << id << "_ARREADY(in): " << (int)ARREADY << std::endl;
}

// return data to master
void masterReadData(
  const unsigned int& ARADDR,
  const unsigned char& ARVALID,
  unsigned char& ARREADY,
  unsigned long& RDATA,
  unsigned char& RVALID,
  unsigned char& RREADY,
  unsigned char& RRESP,
  unsigned char& RLAST,
  unsigned char& ARLEN,
  unsigned char& ARSIZE,
  unsigned char& ARBURST){

  if(readQ.size()>0 && RREADY){
    Transaction& t = readQ.front();
    
    RDATA = *(unsigned long*)(&memory[t.addr]);
    RVALID = true;
    std::cout << "Service Read Addr: " << t.addr << " data: " << RDATA << " remaining_burst: " << t.burst << " outstanding_requests: " << readQ.size() << std::endl;

    t.burst--;
    t.addr+=8;
    
    if(t.burst==0){
      readQ.pop();
    }
  }else if(readQ.size()>0 && RREADY){
    std::cout << readQ.size() << " outstanding read requests, but IP isn't ready" << std::endl;
  }else{
    std::cout << "no outstanding read requests" << std::endl;
    RVALID = false;
  }
}

// service read requests from master
void masterReadReq(
  const unsigned int& ARADDR,
  const unsigned char& ARVALID,
  unsigned char& ARREADY,
  unsigned long& RDATA,
  unsigned char& RVALID,
  unsigned char& RREADY,
  unsigned char& RRESP,
  unsigned char& RLAST,
  unsigned char& ARLEN,
  unsigned char& ARSIZE,
  unsigned char& ARBURST){

  if(ARVALID){
    // read request
    Transaction t;
    assert(ARSIZE==3);
    assert(ARBURST==1);
    t.addr = ARADDR;
    t.burst = ARLEN+1;
    std::cout << "Read Request addr:" << t.addr << "/" << std::hex << t.addr << std::dec << " burst:" << t.burst << std::endl;
    std::cout << "Read Request addr (base rel):" << (t.addr-MEMBASE) << "/" << std::hex << (t.addr-MEMBASE) << std::dec << " burst:" << t.burst << std::endl;

    t.addr -= MEMBASE;

    if(t.addr>=MEMSIZE){
      std::cout << "Segmentation fault on read!" << std::endl;
      exit(1);
    }
    
    readQ.push(t);
  }
}

// return data to master
void masterWriteData(
  unsigned int& AWADDR,
  unsigned char& AWVALID,
  unsigned char& AWREADY,
  unsigned long& WDATA,
  unsigned char& WVALID,
  unsigned char& WREADY,
  unsigned char& BRESP,
  unsigned char& BVALID,
  unsigned char& BREADY,
  unsigned char& WSTRB,
  unsigned char& WLAST,
  unsigned char& AWLEN,
  unsigned char& AWSIZE,
  unsigned char& AWBURST){

  assert(WREADY); // we drive this... should always be true
  
  if( writeQ.size()>0 && WVALID ){
    Transaction& t = writeQ.front();

    *(unsigned long*)(&memory[t.addr]) = WDATA;
    std::cout << "Accept Write, Addr: " << t.addr << " data: " << WDATA << " remaining_burst: " << t.burst << " outstanding_requests: " << writeQ.size() << std::endl;

    t.burst--;
    t.addr+=8;
    
    if(t.burst==0){
      writeQ.pop();
    }
  }else if( writeQ.size()<=0 && WVALID ){
    std::cout << "Error: attempted to write data, but there was no outstanding write addresses!" << std::endl;
    exit(1);
  }else{
    std::cout << "no write request" << std::endl;
  }
}

void masterWriteReq(
  unsigned int& AWADDR,
  unsigned char& AWVALID,
  unsigned char& AWREADY,
  unsigned long& WDATA,
  unsigned char& WVALID,
  unsigned char& WREADY,
  unsigned char& BRESP,
  unsigned char& BVALID,
  unsigned char& BREADY,
  unsigned char& WSTRB,
  unsigned char& WLAST,
  unsigned char& AWLEN,
  unsigned char& AWSIZE,
  unsigned char& AWBURST){

  if(AWVALID){
    assert(AWSIZE==3);
    assert(AWBURST==1);
    assert(WSTRB==255);
    
    Transaction t;
    t.addr = AWADDR;
    t.burst = AWLEN+1;
    std::cout << "Write Request addr:" << t.addr << "/" << std::hex << t.addr << std::dec << " burst:" << t.burst << std::endl;
    std::cout << "Write Request addr (base rel):" << (t.addr-MEMBASE) << "/" << std::hex << (t.addr-MEMBASE) << std::dec << " burst:" << t.burst << std::endl;

    t.addr -= MEMBASE;

    if(t.addr>=MEMSIZE){
      std::cout << "Segmentation fault on write!" << std::endl;
      exit(1);
    }

    writeQ.push(t);
  }
}

void step(VERILATORCLASS* top){
  top->IP_CLK = 0;
  top->eval();
  top->IP_CLK = 1;
  top->eval();
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv); 

  if(argc!=4){
    printf("Usage: XXX.verilator infile outfile simCycles");
    exit(1);
  }

  VERILATORCLASS* top = new VERILATORCLASS;

  bool CLK = false;

  int simCycles = atoi(argv[3]);
  
  FILE* infile = fopen(argv[1],"rb");


  if(infile==NULL){printf("could not open input '%s'\n", argv[1]);}

  fseek(infile, 0L, SEEK_END);
  unsigned long insize = ftell(infile);
  fseek(infile, 0L, SEEK_SET);
  
  memory = (unsigned char*)malloc(MEMSIZE);
  fread( memory, insize, 1, infile );
  fclose( infile );
  
  unsigned long totalCycles = 0;

  // NOTE: you'd think we could check for overflows (too many output packets), but actually we can't
  // some of our modules start producing data immediately for the next frame, which is valid behavior (ie pad)

  printSlave(S0LIST);
  
  for(int i=0; i<100; i++){
    CLK = !CLK;

    top->IP_CLK = CLK;
    top->IP_ARESET_N = false;
    //top->SAXI0_ARREADY = true;
    //top->SAXI0_AWREADY = true;
    top->SAXI0_AWVALID = false;
    top->SAXI0_ARVALID = false;
    top->SAXI0_BREADY = true;
    top->SAXI0_RREADY = true;
    //top->SAXI0_WREADY = true;

    top->MAXI0_ARREADY = true;
    top->MAXI0_RREADY = true;
    top->MAXI0_AWREADY = true;
    top->MAXI0_WREADY = true;
    top->MAXI0_BREADY = true;
    
    top->eval();
  }

  top->IP_ARESET_N=true;
  step(top);
  printSlave(S0LIST);

  step(top);
  printSlave(S0LIST);

  step(top);
  printSlave(S0LIST);
  
  // send start cmd
  top->SAXI0_AWADDR = 0xA0000000;
  top->SAXI0_AWVALID = true;
  step(top);
  printSlave(S0LIST);

  assert(top->SAXI0_WREADY==1);
  top->SAXI0_WDATA = 1;
  top->SAXI0_WVALID = 1;
  step(top);

  top->SAXI0_AWVALID = false;
  step(top);
    
  while (!Verilated::gotFinish() && totalCycles<simCycles ) {
    if(CLK){
      // feed data in
      masterReadData(
        top->MAXI0_ARADDR,
        top->MAXI0_ARVALID,
        top->MAXI0_ARREADY,
        top->MAXI0_RDATA,
        top->MAXI0_RVALID,
        top->MAXI0_RREADY,
        top->MAXI0_RRESP,
        top->MAXI0_RLAST,
        top->MAXI0_ARLEN,
        top->MAXI0_ARSIZE,
        top->MAXI0_ARBURST);

      masterWriteData(
        top->MAXI0_AWADDR,
        top->MAXI0_AWVALID,
        top->MAXI0_AWREADY,
        top->MAXI0_WDATA,
        top->MAXI0_WVALID,
        top->MAXI0_WREADY,
        top->MAXI0_BRESP,
        top->MAXI0_BVALID,
        top->MAXI0_BREADY,
        top->MAXI0_WSTRB,
        top->MAXI0_WLAST,
        top->MAXI0_AWLEN,
        top->MAXI0_AWSIZE,
        top->MAXI0_AWBURST);

      // it's possible the pipeline has 0 cycle delay. in which case, we need to eval the async stuff here.
      top->eval();

        printMasterRead(M0LIST);
  

      // get data out
      masterReadReq(
        top->MAXI0_ARADDR,
        top->MAXI0_ARVALID,
        top->MAXI0_ARREADY,
        top->MAXI0_RDATA,
        top->MAXI0_RVALID,
        top->MAXI0_RREADY,
        top->MAXI0_RRESP,
        top->MAXI0_RLAST,
        top->MAXI0_ARLEN,
        top->MAXI0_ARSIZE,
        top->MAXI0_ARBURST);

      masterWriteReq(
        top->MAXI0_AWADDR,
        top->MAXI0_AWVALID,
        top->MAXI0_AWREADY,
        top->MAXI0_WDATA,
        top->MAXI0_WVALID,
        top->MAXI0_WREADY,
        top->MAXI0_BRESP,
        top->MAXI0_BVALID,
        top->MAXI0_BREADY,
        top->MAXI0_WSTRB,
        top->MAXI0_WLAST,
        top->MAXI0_AWLEN,
        top->MAXI0_AWSIZE,
        top->MAXI0_AWBURST);
                     
      
      totalCycles++;
    }

    CLK = !CLK;

    top->IP_CLK = CLK;
    top->IP_ARESET_N = true;
    top->eval();
  }

  top->final();
  delete top;

  printf("Cycles: %d\n", (int)totalCycles);

  FILE* outfile = fopen(argv[2],"wb");
  if(outfile==NULL){printf("could not open output '%s'\n", argv[2]);}
  fwrite( memory+8192, 8192, 1, outfile);
  fclose(outfile);
  
  if(readQ.size()>0){
    std::cout << "Error, outstanding read requests at end of time! cnt:" << readQ.size() << std::endl;
    exit(1);
  }

  if(writeQ.size()>0){
    std::cout << "Error, outstanding write requests at end of time! cnt:" << writeQ.size() << std::endl;
    exit(1);
  }
}
