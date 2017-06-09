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

// databits: uses the same addressing scheme as verilog
template<typename T>
void setValid(T* signal, unsigned int databits, bool valid){
  // for this verilator data type, we should have < 16 bits
  assert(databits<=sizeof(T)*8);

  if(valid){
    *signal |= ((T)(1)<<databits);
  }else{
    *signal &= ~((T)(1)<<databits);
  }    
}

template<int N>
void setValid(WData (*signal)[N], unsigned int databits, bool valid){
  assert(databits<N*32);
  assert(databits%32==0);
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
  assert(databits<N*32);
  assert(databits%32==0);
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
    *signal |= (inp << (i*8));
  }
}



template<int N>
void setData(WData (*signal)[N], unsigned int databits, FILE* file){
  assert(databits==64);
  //assert(N==2);

  for(int j=0; j<2; j++){
    (*signal)[j]=0;
    for(int i=0; i<4; i++){
      unsigned long inp = fgetc(file);
      assert(inp!=EOF);
      (*signal)[j] |= (inp << i*8);
    }
  }
}


// startPos is in verilog index format
template<typename T>
void setDataBuf(T* signal, unsigned int databits, unsigned int startPos, unsigned char* data){
  assert(databits+startPos<=sizeof(T)*8);

  if(databits==0){
return;
  }

  int readBytes = bitsToBytes(databits);
  assert(databits % 8 == 0);
  //xassert(startPos%8==0);

  for(int i=0; i<readBytes; i++){
    // assume little endian (x86 style) in the file
    T inp = data[i];
    T mask = (T)(255) << i*8+startPos;
    mask = ~mask;
    *signal &= mask;
    *signal |= (inp << (i*8+startPos));
  }
}

template<int N>
void setDataBuf(WData (*signal)[N], unsigned int databits, unsigned int startPos, unsigned char* data){
  assert(startPos%32==0);
  assert(databits%32==0);
  assert(startPos+databits < N*32);

  if(databits==0){
return;
  }

  for(int j=0; j<(databits)/32; j++){
    for(int i=0; i<4; i++){
      unsigned long inp = data[j*4+i];
      (*signal)[j+(startPos/32)] |= (inp << (i*8));
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
  assert(databits%32==0);
    
  for(int j=0; j<databits/32; j++){
    for(int i=0; i<4; i++){
      unsigned char ot = (*signal)[j] >> (i*8);
      fputc(ot,file);
    }
  }
}

// extract 32 bits of data, starting at bit 'startbit'
template<int N>
unsigned int getUintData( WData (*signal)[N], unsigned int startbit){
  assert(false);
}

template<typename T>
unsigned int getUintData(T* signal, unsigned int startbit){
  assert(startbit+32<=sizeof(T)*8);

  unsigned int m = 0;
  m = ~m;
  T mask = m;
  mask <<= startbit;

  T dat = (*signal) & mask;
  dat >>= startbit;
  
  return dat;
}

void* readFile(char* filename){
  FILE *f = fopen(filename, "rb");
  fseek(f, 0, SEEK_END);
  long fsize = ftell(f);
  fseek(f, 0, SEEK_SET);  //same as rewind(f);

  void *buf = malloc(fsize);
  fread(buf, fsize, 1, f);
  fclose(f);

  return buf;
}
