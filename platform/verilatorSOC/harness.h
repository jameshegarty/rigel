#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct{unsigned int addr; unsigned int burst; unsigned short id;} Transaction;

typedef struct{int front; int rear; int itemCount; unsigned char* data; unsigned int dataBytes;} Queue;

const unsigned int QUEUE_MAX = 1024*1024;

#define READ_SLAVEOUT_PORTS unsigned char* ARREADY, unsigned long* RDATA,  unsigned char* RVALID, unsigned char* RRESP,  unsigned char* RLAST, unsigned short* RID
#define READ_SLAVEOUT_PORTS_CONST const unsigned char* ARREADY, const unsigned long* RDATA,  const unsigned char* RVALID, const unsigned char* RRESP,  const unsigned char* RLAST, const unsigned short* RID
#define READ_SLAVEIN_PORTS_CONST   const unsigned int* ARADDR, const unsigned char* ARVALID, const unsigned char* RREADY, const unsigned char* ARLEN, const unsigned char* ARSIZE, const unsigned char* ARBURST, const unsigned short* ARID


#define WRITE_SLAVEOUT_PORTS unsigned char* AWREADY, unsigned char* WREADY, unsigned char* BRESP, unsigned char* BVALID, unsigned short* BID
#define WRITE_SLAVEOUT_PORTS_CONST const unsigned char* AWREADY, const unsigned char* WREADY, const unsigned char* BRESP, const unsigned char* BVALID, const unsigned short* BID


#define WRITE_SLAVEIN_PORTS_CONST const unsigned int* AWADDR, const unsigned char* AWVALID, const unsigned long* WDATA, const unsigned char* WVALID, const unsigned char* BREADY, const unsigned char* WSTRB, const unsigned char* WLAST, const unsigned char* AWLEN, const unsigned char* AWSIZE, const unsigned char* AWBURST, const unsigned short* AWID


unsigned char* QPeek(Queue* q) {
  return q->data+(q->front*q->dataBytes);
}

//bool isEmpty() {
//  return itemCount == 0;
//}

bool QFull(Queue* q) {
  return q->itemCount == QUEUE_MAX;
}

int QSize(Queue* q) {
  return q->itemCount;
}

void QPush(Queue* q, unsigned char* data) {

  if(!QFull(q)) {

    if(q->rear == QUEUE_MAX-1) {
      q->rear = -1;
    }

    //intArray[++rear] = data;
    q->rear++;
    memcpy(q->data+(q->rear*q->dataBytes), data, q->dataBytes);
    q->itemCount++;
  }else{
    printf("Q is full!\n");
    exit(1);
  }
}

unsigned char* QPop(Queue* q) {
  //int data = intArray[front++];
  unsigned char* data = q->data+(q->front*q->dataBytes);
  q->front++;

  if(q->front == QUEUE_MAX) {
    q->front = 0;
  }

  q->itemCount--;
  return data;
}

void QInit(Queue* q, unsigned int dataBytes){
  q->front=0;
  q->rear=-1;
  q->itemCount=0;
  q->dataBytes = dataBytes;
  q->data = (unsigned char*)malloc(QUEUE_MAX*dataBytes);
}

//unsigned int MEMBASE = 0x30008000;
//unsigned int MEMSIZE = 8192*2;
//unsigned char* memory;

const unsigned int PORTS = 4;
//std::queue<Transaction> readQ[PORTS];
//std::queue<Transaction> writeQ[PORTS];
Queue readQ[PORTS];
Queue writeQ[PORTS];

unsigned int masterBytesRead[PORTS];
unsigned int masterBytesWritten[PORTS];

unsigned int cyclesSinceWrite[PORTS];

float randf(){ return (float)rand()/(float)(RAND_MAX); }

unsigned int bytesRead(){
  unsigned int b = 0;
  for(int i=0; i<PORTS; i++){
    b+=masterBytesRead[i];
  }
  return b;
}

unsigned int bytesWritten(){
  unsigned int b = 0;
  for(int i=0; i<PORTS; i++){
    b+=masterBytesWritten[i];
  }
  return b;
}

void init(){
  for(int i=0; i<PORTS; i++){
    QInit(&readQ[i], sizeof(Transaction));
    QInit(&writeQ[i], sizeof(Transaction));
  }

  for(int i=0; i<PORTS; i++){
    masterBytesRead[i]=0;
    masterBytesWritten[i]=0;
    cyclesSinceWrite[i]=0;
  }
}

void printSlave(
  int id,
  unsigned char* IP_CLK,
  unsigned char* IP_ARESET_N,
  unsigned int* ARADDR,
  unsigned char* ARVALID,
  unsigned char* ARREADY,
  unsigned int* AWADDR,
  unsigned char* AWVALID,
  unsigned char* AWREADY,
  unsigned int* RDATA,
  unsigned char* RVALID,
  unsigned char* RREADY,
  unsigned char* BRESP,
  unsigned char* BVALID,
  unsigned char* BREADY,
  unsigned char* RRESP,
  unsigned char* WVALID,
  unsigned char* WREADY){

  printf("----------------------\n");
  printf("IP_CLK(in): %d\n",(int)*IP_CLK);
  printf("IP_ARESET_N(in): %d\n",(int)*IP_ARESET_N);
  printf("S_ARADDR(in): %d/%#x\n",*ARADDR, *ARADDR);
  printf("S_ARVALID(in): %d\n",(int)*ARVALID);
  printf("S_ARREADY(out): %d\n",(int)*ARREADY);
  printf("S_AWADDR(in): %d/%#x\n", *AWADDR, *AWADDR );
  printf("S_AWVALID(in): %d\n",(int)*AWVALID);
  printf("S_AWREADY(out): %d\n",(int)*AWREADY);
  printf("S_RDATA(out): %d\n",*RDATA);
  printf("S_RVALID(out): %d\n",(int)*RVALID);
  printf("S_RREADY(in): %d\n",(int)*RREADY);
  printf("S_BRESP(out): %d\n",(int)*BRESP);
  printf("S_BVALID(out): %d\n",(int)*BVALID);
  printf("S_WVALID(in): %d\n",(int)*WVALID);
  printf("S_WREADY(out): %d\n",(int)*WREADY);
}

void resetSlave(
  int id,
  unsigned char* IP_CLK,
  unsigned char* IP_ARESET_N,
  unsigned int* ARADDR,
  unsigned char* ARVALID,
  unsigned char* ARREADY,
  unsigned int* AWADDR,
  unsigned char* AWVALID,
  unsigned char* AWREADY,
  unsigned int* RDATA,
  unsigned char* RVALID,
  unsigned char* RREADY,
  unsigned char* BRESP,
  unsigned char* BVALID,
  unsigned char* BREADY,
  unsigned char* RRESP,
  unsigned char* WVALID,
  unsigned char* WREADY){

  *AWVALID = false;
  *ARVALID = false;
  *BREADY = true;
  *RREADY = true;
}

bool checkSlaveWriteResponse(
  int id,
  unsigned char* IP_CLK,
  unsigned char* IP_ARESET_N,
  unsigned int* ARADDR,
  unsigned char* ARVALID,
  unsigned char* ARREADY,
  unsigned int* AWADDR,
  unsigned char* AWVALID,
  unsigned char* AWREADY,
  unsigned int* RDATA,
  unsigned char* RVALID,
  unsigned char* RREADY,
  unsigned char* BRESP,
  unsigned char* BVALID,
  unsigned char* BREADY,
  unsigned char* RRESP,
  unsigned char* WVALID,
  unsigned char* WREADY){

  if( *BVALID && *BRESP==2){
    printf("Slave %d Error", id);
    exit(1);
  }else if( *BVALID && *BRESP==0){
    return true;
  }else if( *BVALID ){
    printf("Slave %d returned strange write respose? %d", id, *BRESP);
    exit(1);
  }

  return false;
}

bool checkSlaveReadResponse(
  int id,
  unsigned char* IP_CLK,
  unsigned char* IP_ARESET_N,
  unsigned int* ARADDR,
  unsigned char* ARVALID,
  unsigned char* ARREADY,
  unsigned int* AWADDR,
  unsigned char* AWVALID,
  unsigned char* AWREADY,
  unsigned int* RDATA,
  unsigned char* RVALID,
  unsigned char* RREADY,
  unsigned char* BRESP,
  unsigned char* BVALID,
  unsigned char* BREADY,
  unsigned char* RRESP,
  unsigned char* WVALID,
  unsigned char* WREADY,
  unsigned int* dataOut){

  if( *RVALID && *RRESP==2){
    printf("Slave %d read Error", id);
    exit(1);
  }else if( *RVALID && *RRESP==0){
    *dataOut = *RDATA;
    return true;
  }else if( *RVALID ){
    printf("Slave %d returned strange read respose? %d", id, *RRESP);
    exit(1);
  }

  return false;
}

bool slaveReadReq(
  unsigned int address,
  int id,
  unsigned char* IP_CLK,
  unsigned char* IP_ARESET_N,
  unsigned int* ARADDR,
  unsigned char* ARVALID,
  unsigned char* ARREADY,
  unsigned int* AWADDR,
  unsigned char* AWVALID,
  unsigned char* AWREADY,
  unsigned int* RDATA,
  unsigned char* RVALID,
  unsigned char* RREADY,
  unsigned char* BRESP,
  unsigned char* BVALID,
  unsigned char* BREADY,
  unsigned char* RRESP,
  unsigned char* WVALID,
  unsigned char* WREADY){

  //  if(*ARREADY==false){
  //    printf("IP_SAXI0_ARREADY should be true\n");
  //    exit(1);
  //  }
  
  *ARVALID = true;
  *ARADDR = address;

  return *ARREADY;
}

void activateMasterRead(READ_SLAVEOUT_PORTS){
  *ARREADY = true;
}

void activateMasterWrite(WRITE_SLAVEOUT_PORTS){
  *AWREADY = true;
  *WREADY = true;
}

void deactivateMasterRead(READ_SLAVEOUT_PORTS){
  *ARREADY = false;
}

void deactivateMasterWrite(WRITE_SLAVEOUT_PORTS){
  *AWREADY = false;
  *WREADY = false;
  *BVALID = false;
}

void printMasterRead(
  int id,
  READ_SLAVEIN_PORTS_CONST,
  READ_SLAVEOUT_PORTS_CONST){

  printf("----------------------\n");
  //printf("IP_CLK(in): " << (int)IP_CLK);
  //printf("IP_ARESET_N(in): " << (int)IP_ARESET_N);
  printf("M%d_ARADDR(out): %d/%#x\n",id,*ARADDR,*ARADDR);
  printf("M%d_ARVALID(out): %d\n",id, (int)*ARVALID);
  printf("M%d_ARREADY(in): %d\n",id, (int)*ARREADY);
  printf("M%d_RVALID(in): %d\n",id, (int)*RVALID);
}

void printMasterWrite(
  int id,
  WRITE_SLAVEIN_PORTS_CONST,
  WRITE_SLAVEOUT_PORTS_CONST){

  printf("----------------------\n");
  printf("M%d_AWADDR(out): %d/%#x\n",id, *AWADDR, *AWADDR);
  printf("M%d_AWVALID(out): %d\n",id,(int)*AWVALID);
  printf("M%d_AWREADY(in): %d\n",id, (int)*AWREADY);
  
  printf("M%d_WDATA(out): %lu/%#lx\n",id, *WDATA, *WDATA);
  printf("M%d_WVALID(out): %d\n",id, (int)*WVALID);
  printf("M%d_WREADY(in): %d\n",id, (int)*WREADY);
}

typedef struct SlaveState{
  unsigned char BVALID;
  unsigned char BRESP;
  unsigned short BID;
} SlaveState;

void initSlaveState(SlaveState* slaveState){
  slaveState->BVALID=false;
  slaveState->BID=42;
}

// return data to master
void masterReadDataDriveOutputs(
  bool verbose,
  unsigned char* memory,
  int port,
  READ_SLAVEOUT_PORTS){
      
  Transaction* t = (Transaction*)QPeek(&readQ[port]);
  *RVALID = (QSize(&readQ[port])>0);
  *RID = t->id;
  *RDATA = *(unsigned long*)(&memory[t->addr]);
}

void masterReadDataLatchFlops(
  bool verbose,
  unsigned char* memory,
  int port,
  READ_SLAVEIN_PORTS_CONST){
  
  if( QSize(&readQ[port])>0 && *RREADY){
    Transaction* t = (Transaction*)QPeek(&readQ[port]);
          
    if(verbose){
      printf("MAXI%d Service Read Addr(base rel):%d data:%lu/0x%lx remaining_burst:%d outstanding_requests:%d\n", port, t->addr, *(unsigned long*)(&memory[t->addr]), *(unsigned long*)(&memory[t->addr]), t->burst, QSize(&readQ[port]));
    }
      
    t->burst--;
    t->addr+=8;

    masterBytesRead[port] += 8; // for debug
      
    if(t->burst==0){
      QPop(&readQ[port]);
    }
  }else if( QSize(&readQ[port]) >0 && *RREADY==false){
    if(verbose){printf("MAXI%d: %d outstanding read requests, but IP isn't ready\n", port, QSize(&readQ[port]) );}
  }else{
    if(verbose){printf("MAXI%d no outstanding read requests\n",port);}
  }
}

// service read requests from master
void masterReadReqDriveOutputs(
  bool verbose,
  unsigned int MEMBASE,
  unsigned int MEMSIZE,
  int port,
  READ_SLAVEOUT_PORTS){

  *ARREADY = true;
}

void masterReadReqLatchFlops(
  bool verbose,
  unsigned int MEMBASE,
  unsigned int MEMSIZE,
  int port,
  READ_SLAVEIN_PORTS_CONST){

  if(*ARVALID){
    // read request
    Transaction t;
    assert(*ARSIZE==3);
    assert(*ARBURST==1);
    t.addr = *ARADDR;
    t.burst = *ARLEN+1;
    t.id = *ARID;
    
    if(verbose){
      printf("MAXI%d Read Request addr:%d/%#x (base rel):%d/%#x burst:%d\n", port, t.addr, t.addr, (t.addr-MEMBASE), (t.addr-MEMBASE), t.burst );
      //std::cout << "MAXI" << port << " Read Request addr (base rel):" << (t.addr-MEMBASE) << "/" << std::hex << "0x" << (t.addr-MEMBASE) << std::dec << " burst:" << t.burst << std::endl;
    }
    
    t.addr -= MEMBASE;

    if(t.addr>=MEMSIZE){
      printf("Segmentation fault on read! Attempted to read address %#x, which is outside of range [%#x,%#x]\n", *ARADDR, MEMBASE, MEMBASE+MEMSIZE);
      exit(1);
    }
    
    QPush(&readQ[port],(unsigned char*)&t);
  }else{
    if(verbose){ printf("MAXI%d no read request!\n",port);}
  }
}

// return data to master
void masterWriteDataDriveOutputs(
  bool verbose,
  unsigned char* memory,
  SlaveState* slaveState,
  int port,
  WRITE_SLAVEOUT_PORTS){

  *WREADY = QSize(&writeQ[port])>0;
  *BVALID = slaveState->BVALID;
  *BRESP = slaveState->BRESP;
  *BID = slaveState->BID;
}

// return error flag (true if error)
bool masterWriteDataLatchFlops(
  bool verbose,
  unsigned char* memory,
  SlaveState* slaveState,
  int port,
  bool checkDataEqual, // in second round, we want to make sure pipeline does exactly the same thing
  WRITE_SLAVEIN_PORTS_CONST){

  //static int BVALIDS_SENT=0;

  if(*BREADY){ // bvalid was accepted
    slaveState->BVALID = false;
  }
  
  if( QSize(&writeQ[port])>0 && *WVALID ){
    Transaction* t = (Transaction*)QPeek(&writeQ[port]);

    if(checkDataEqual && (*(unsigned long*)(&memory[t->addr]) != *WDATA) ){
      printf("Write Error in second round: Data is different than first round! pipeline behavior may have changed! addr %d/%#x orig: %#018lx new: %#018lx\n",t->addr,t->addr,*(unsigned long*)(&memory[t->addr]),*WDATA);
      *(unsigned long*)(&memory[t->addr]) = *WDATA;
      return true;
    }
    
    *(unsigned long*)(&memory[t->addr]) = *WDATA;

    if(verbose){
      printf("MAXI%d Accept Write, Addr(base rel): %u/%#0x data: %lu/%#018lx remaining_burst: %d outstanding_requests: %d\n", port, t->addr, t->addr, *WDATA, *WDATA, t->burst, QSize(&writeQ[port]) );
    }
    
    t->burst--;
    t->addr+=8;

    masterBytesWritten[port] += 8; // for debug
          
    if(t->burst==0){
      // write transaction is done
      QPop(&writeQ[port]);
      slaveState->BVALID = true;
      slaveState->BRESP = 0;
      slaveState->BID = t->id;
      //BVALIDS_SENT++;

      if(*BREADY==0){
        printf("MAXI NYI - BREADY is false\n");
        return true;
      }
      //    }else{
      //      slaveState->BVALID = false;
    }

    cyclesSinceWrite[port] = 0;
  }else{
    if(verbose){ printf("MAXI%d no write data (%d outstanding requests)\n",port,QSize(&writeQ[port]));}

    cyclesSinceWrite[port]++;
    //    slaveState->BVALID = false;

    if( cyclesSinceWrite[port]>200000 && QSize(&writeQ[port])>0 ){
      Transaction* t = (Transaction*)QPeek(&writeQ[port]);
      printf("MAXI%d write port is stalled out? No data sent for %d cycles (%d outstanding write requests, top addr %d)\n",port,cyclesSinceWrite[port],QSize(&writeQ[port]),t->addr);
      return true;
    }
  }

  return false;
}

void masterWriteReqDriveOutputs(
  bool verbose,
  unsigned int MEMBASE,
  unsigned int MEMSIZE,
  int port,
  WRITE_SLAVEOUT_PORTS){

  *AWREADY = true;
}

void masterWriteReqLatchFlops(
  bool verbose,
  unsigned int MEMBASE,
  unsigned int MEMSIZE,
  int port,
  WRITE_SLAVEIN_PORTS_CONST){

  if(*AWVALID){
    assert(*AWSIZE==3);
    assert(*AWBURST==1);
    assert(*WSTRB==255);
    
    Transaction t;
    t.addr = *AWADDR;
    t.burst = *AWLEN+1;
    t.id = *AWID;

    if( verbose ){
      printf("MAXI%d Write Request addr:%d/%#x (base rel):%d/%#x burst:%d\n", port, t.addr, t.addr, (t.addr-MEMBASE), (t.addr-MEMBASE), t.burst);
    }

    unsigned long origAddr = t.addr;
    t.addr -= MEMBASE;

    if(t.addr>=MEMSIZE){
      printf("MAXI%d Segmentation fault on write! addr:%lu/%#lx segment:%#x-%#x\n",port,origAddr,origAddr,MEMBASE,MEMBASE+MEMSIZE);
      exit(1);
    }

    //writeQ[port].push(t);
    QPush(&writeQ[port],(unsigned char*)&t);
  }else{
    if(verbose){printf("MAXI%d no write request\n",port);}
  }
}

void loadFile( char* filename, unsigned char* memory, unsigned int addrOffset ){
  FILE* infile = fopen(filename,"rb");
  if(infile==NULL){printf("could not open input '%s'\n", filename);}
  fseek(infile, 0L, SEEK_END);
  unsigned long insize = ftell(infile);
  fseek(infile, 0L, SEEK_SET);
  fread( memory+addrOffset, insize, 1, infile );
  fclose( infile );
  
  //std::cout << "Input File " << inputCount << ": filename=" << argv[curArg] << " address=0x" << std::hex << addr << " addressOffset=0x" << addrOffset << std::dec << " bytes=" << insize <<std::endl;
  printf("Input File: filename=%s addressOffset=0x%x bytes=%lu\n",filename,addrOffset,insize);
}

void saveFile( const char* filename, unsigned char* memory, unsigned int addrOffset, unsigned int bytes ){
  if(bytes==0){
    printf("Error saving file '%s'! Has 0 byte size?\n",filename);
    exit(1);
  }
  
  FILE* outfile = fopen( filename, "wb" );
  if(outfile==NULL){printf("could not open output '%s'\n", filename );}
  fwrite( memory+addrOffset, bytes, 1, outfile);
  fclose(outfile);

  //std::cout << "Output File " << outputCount << ": filename=" << outFilename << " address=0x" << std::hex << addr << " addressOffset=0x" << addrOffset << std::dec << " W=" << w <<" H="<<h<<" bitsPerPixel="<<bitsPerPixel<<" bytes="<<bytes<<std::endl;
  printf("Output File: filename=%s addressOffset=0x%x bytes=%d\n",filename,addrOffset,bytes);
}

// checkWriteOnly: only check that the write port is idle (don't check on read port)
bool checkPorts(bool checkWriteOnly){
  bool errored = false;
  
  for(int port=0; port<PORTS; port++){
    if( QSize(&readQ[port])>0 && checkWriteOnly==false){
      //std::cout << "MAXI" << port << " Error, outstanding read requests at end of time! cnt:" << readQ[port].size() << " bytesRead: " << masterBytesRead[port] << std::endl;
      Transaction* t = (Transaction*)QPeek(&readQ[port]);
      printf("MAXI%d Error, outstanding read requests at end of time! cnt:%d nextTransactionBurst:%d nextAddr:%x nextId:%d bytesRead: %d\n", port, QSize(&readQ[port]), t->burst, t->addr, t->id, masterBytesRead[port] );
      errored = true;
    }
    
    if( QSize(&writeQ[port])>0){
      //std::cout << "MAXI" << port << " Error, outstanding write requests at end of time! cnt:" << writeQ[port].size() << " bytesWritten: " << masterBytesWritten[port] << std::endl;
      Transaction* t = (Transaction*)QPeek(&writeQ[port]);
      printf("MAXI%d Error, outstanding write requests at end of time! cnt:%d nextTransactionAddr:%d nextTransactionBurst:%d bytesWrittenOnThisPort:%d bytesReadOnAllPorts:%d\n",port, QSize(&writeQ[port]), t->addr, t->burst, masterBytesWritten[port], bytesRead() );
      errored = true;
    }
  }

  return errored;
}
