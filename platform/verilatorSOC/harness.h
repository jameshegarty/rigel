typedef struct{unsigned int addr; unsigned int burst;} Transaction;

typedef struct{int front; int rear; int itemCount; unsigned char* data; unsigned int dataBytes;} Queue;

const unsigned int QUEUE_MAX = 1024*1024;

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

unsigned int MEMBASE = 0x30008000;
unsigned int MEMSIZE = 8192*2;
unsigned char* memory;

const unsigned int PORTS = 4;
//std::queue<Transaction> readQ[PORTS];
//std::queue<Transaction> writeQ[PORTS];
Queue readQ[PORTS];
Queue writeQ[PORTS];

unsigned int masterBytesRead[4];
unsigned int masterBytesWritten[4];

float randf(){ return (float)rand()/(float)(RAND_MAX); }

void initQueues(){
  for(int i=0; i<PORTS; i++){
    QInit(&readQ[i], sizeof(Transaction));
    QInit(&writeQ[i], sizeof(Transaction));
  }
}
  
void printSlave(
  int id,
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
  unsigned char& RREADY,
  unsigned char& BRESP,
  unsigned char& BVALID,
  unsigned char& BREADY){

  std::cout << "----------------------" << std::endl;
  std::cout << "IP_CLK(in): " << (int)IP_CLK << std::endl;
  std::cout << "IP_ARESET_N(in): " << (int)IP_ARESET_N << std::endl;
  std::cout << "S_ARADDR(in): " << ARADDR << std::endl;
  std::cout << "S_ARVALID(in): " << (int)ARVALID << std::endl;
  std::cout << "S_ARREADY(out): " << (int)ARREADY << std::endl;
  std::cout << "S_AWADDR(in): " << AWADDR << "/" << std::hex << "0x" << AWADDR  << std::dec<< std::endl;
  std::cout << "S_AWVALID(in): " << (int)AWVALID << std::endl;
  std::cout << "S_AWREADY(out): " << (int)AWREADY << std::endl;
  std::cout << "S_RDATA(out): " << RDATA << std::endl;
  std::cout << "S_RVALID(out): " << (int)RVALID << std::endl;
  std::cout << "S_RREADY(in): " << (int)RREADY << std::endl;
  std::cout << "S_BRESP(out): " << (int)BRESP << std::endl;
  std::cout << "S_BVALID(out): " << (int)BRESP << std::endl;
}

void resetSlave(
  int id,
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
  unsigned char& RREADY,
  unsigned char& BRESP,
  unsigned char& BVALID,
  unsigned char& BREADY){

  AWVALID = false;
  ARVALID = false;
  BREADY = true;
  RREADY = true;
}

bool checkSlaveResponse(
  int id,
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
  unsigned char& RREADY,
  unsigned char& BRESP,
  unsigned char& BVALID,
  unsigned char& BREADY){

  if( BVALID && BRESP==2){
    std::cout << "Slave " << id << " Error" << std::endl;
    exit(1);
  }else if( BVALID && BRESP==0){
    return true;
  }else if( BVALID ){
    std::cout << "Slave " << id << " returned strange respose? " << BRESP << std::endl;
    exit(1);
  }

  return false;
}

void activateMasterRead(
  int port,
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

  ARREADY = true;
  RREADY = true;
}

void activateMasterWrite(
  int id,
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

  AWREADY = true;
  WREADY = true;
  BREADY = true;
}

void deactivateMasterRead(
  int port,
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

  ARREADY = false;
  RREADY = false;
}

void deactivateMasterWrite(
  int id,
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

  AWREADY = false;
  WREADY = false;
  BREADY = false;
}

void printMasterRead(
  int id,
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

  std::cout << "----------------------" << std::endl;
  //std::cout << "IP_CLK(in): " << (int)IP_CLK << std::endl;
  //std::cout << "IP_ARESET_N(in): " << (int)IP_ARESET_N << std::endl;
  std::cout << "M" << id << "_ARADDR(out): " << ARADDR << "/" << std::hex  << "0x" << ARADDR  << std::dec<< std::endl;
  std::cout << "M" << id << "_ARVALID(out): " << (int)ARVALID << std::endl;
  std::cout << "M" << id << "_ARREADY(in): " << (int)ARREADY << std::endl;
}

void printMasterWrite(
  int id,
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

  std::cout << "----------------------" << std::endl;
  std::cout << "M" << id << "_AWADDR(out): " << AWADDR << "/" << std::hex  << "0x" << AWADDR  << std::dec<< std::endl;
  std::cout << "M" << id << "_AWVALID(out): " << (int)AWVALID << std::endl;
  std::cout << "M" << id << "_AWREADY(in): " << (int)AWREADY << std::endl;

  std::cout << "M" << id << "_WDATA(out): " << WDATA << "/" << std::hex  << "0x" << WDATA  << std::dec<< std::endl;
  std::cout << "M" << id << "_WVALID(out): " << (int)WVALID << std::endl;
  std::cout << "M" << id << "_WREADY(in): " << (int)WREADY << std::endl;
}

// return data to master
void masterReadData(
  bool verbose,
  int port,
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

  if( QSize(&readQ[port])>0 && RREADY){
    if(false && randf()>0.2f){
      RVALID = false;
    }else{
      Transaction* t = (Transaction*)QPeek(&readQ[port]);
      
      RDATA = *(unsigned long*)(&memory[t->addr]);
      RVALID = true;
      
      if(verbose){
        //std::cout << "MAXI" << port << " Service Read Addr: " << t.addr << " data: " << RDATA << " remaining_burst: " << t.burst << " outstanding_requests: " << readQ[port].size() << std::endl;
      }
      
      t->burst--;
      t->addr+=8;

      masterBytesRead[port] += 8; // for debug
      
      if(t->burst==0){
        QPop(&readQ[port]);
      }
    }
  }else if( QSize(&readQ[port]) >0 && RREADY){
    printf("MAXI%d: %d outstanding read requests, but IP isn't ready\n", port, QSize(&readQ[port]) );
  }else{
    //if(verbose){std::cout << "MAXI" << port << " no outstanding read requests" << std::endl;}
    RVALID = false;
  }
}

// service read requests from master
void masterReadReq(
  bool verbose,
  int port,
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

    if(verbose){
      //std::cout << "MAXI" << port << " Read Request addr:" << t.addr << "/" << std::hex << "0x" << t.addr << std::dec << " burst:" << t.burst << std::endl;
      //std::cout << "MAXI" << port << " Read Request addr (base rel):" << (t.addr-MEMBASE) << "/" << std::hex << "0x" << (t.addr-MEMBASE) << std::dec << " burst:" << t.burst << std::endl;
    }
    
    t.addr -= MEMBASE;

    if(t.addr>=MEMSIZE){
      printf("Segmentation fault on read! Attempted to read address %#x, which is outside of range [%#x,%#x]\n", ARADDR, MEMBASE, MEMBASE+MEMSIZE);
      exit(1);
    }
    
    //readQ[port].push(t);
    QPush(&readQ[port],(unsigned char*)&t);
  }else{
    if(verbose){ printf("MAXI%d no read request!",port);}
  }
}

// return data to master
void masterWriteData(
  bool verbose,
  int port,
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
  
  if( QSize(&writeQ[port])>0 && WVALID ){
    Transaction* t = (Transaction*)QPeek(&writeQ[port]);

    *(unsigned long*)(&memory[t->addr]) = WDATA;

    if(verbose){
      //std::cout << "MAXI" << port << " Accept Write, Addr: " << t.addr << "/" << std::hex << "0x" << std::dec << t.addr << " data: " << WDATA << " remaining_burst: " << t.burst << " outstanding_requests: " << writeQ[port].size() << std::endl;
    }
    
    t->burst--;
    t->addr+=8;

    masterBytesWritten[port] += 8; // for debug
          
    if(t->burst==0){
      QPop(&writeQ[port]);
    }
  }else if( QSize(&writeQ[port])<=0 && WVALID ){
    printf("Error: attempted to write data, but there was no outstanding write addresses! (master port %d)\n",port);
    exit(1);
  }else{
    if(verbose){ printf("MAXI%d no write data (%d outstanding requests)\n",port,QSize(&writeQ[port]));}
  }
}

void masterWriteReq(
  bool verbose,
  int port,
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

    if(verbose){
      std::cout << "MAXI" << port << " Write Request addr:" << t.addr << "/" << std::hex << "0x" << t.addr << std::dec << " burst:" << t.burst << std::endl;
      std::cout << "MAXI" << port << " Write Request addr (base rel):" << (t.addr-MEMBASE) << "/" << std::hex << "0x" << (t.addr-MEMBASE) << std::dec << " burst:" << t.burst << std::endl;
    }
    
    t.addr -= MEMBASE;

    if(t.addr>=MEMSIZE){
      std::cout << "MAXI" << port << " Segmentation fault on write!" << std::endl;
      exit(1);
    }

    //writeQ[port].push(t);
    QPush(&writeQ[port],(unsigned char*)&t);
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
  printf("Input File: filename=%s addressOffset=0x%x bytes=%d\n",filename,addrOffset,insize);
}

void saveFile( const char* filename, unsigned char* memory, unsigned int addrOffset, unsigned int bytes ){
  FILE* outfile = fopen( filename, "wb" );
  if(outfile==NULL){printf("could not open output '%s'\n", filename );}
  fwrite( memory+addrOffset, bytes, 1, outfile);
  fclose(outfile);

  //std::cout << "Output File " << outputCount << ": filename=" << outFilename << " address=0x" << std::hex << addr << " addressOffset=0x" << addrOffset << std::dec << " W=" << w <<" H="<<h<<" bitsPerPixel="<<bitsPerPixel<<" bytes="<<bytes<<std::endl;
  printf("Output File: filename=%s addressOffset=0x%x bytes=%d\n",filename,addrOffset,bytes);
}

bool checkPorts(){
  bool errored = false;
  
  for(int port=0; port<PORTS; port++){
    if( QSize(&readQ[port])>0){
      //std::cout << "MAXI" << port << " Error, outstanding read requests at end of time! cnt:" << readQ[port].size() << " bytesRead: " << masterBytesRead[port] << std::endl;
      printf("MAXI%d Error, outstanding read requests at end of time! cnt:%d bytesRead: %d\n", port, QSize(&readQ[port]), masterBytesRead[port] );
      errored = true;
    }
    
    if( QSize(&writeQ[port])>0){
      //std::cout << "MAXI" << port << " Error, outstanding write requests at end of time! cnt:" << writeQ[port].size() << " bytesWritten: " << masterBytesWritten[port] << std::endl;
      printf("MAXI%d Error, outstanding write requests at end of time! cnt:%d bytesWritten:%d\n",port, QSize(&writeQ[port]),masterBytesWritten[port] );
      errored = true;
    }
  }

  return errored;
}
