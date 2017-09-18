
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
    printf("NYI - bits to bytes %d\n",bits);
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
  assert(databits%8==0);
  assert(startPos+databits < N*32);
  assert(sizeof(WData)==4);
  
  if(databits==0){
return;
  }

  int startWord = startPos/32; // floor
      
  for(int j=0; j<(databits)/8; j++){
    unsigned long inp = data[j];
    unsigned int sft = ((j%4)*8 + (startPos-startWord*32));

    unsigned long mask = 255;
    
    assert(sft<=56);
    inp <<= sft;
    mask <<= sft;

    mask = ~mask;
    
    // 'trick' to write bytes that straddle the 32 bit boundaries
    for(int i=0; i<2; i++){
      (*signal)[(j/4)+startWord+i] &= mask >> (i*32);
      (*signal)[(j/4)+startWord+i] |= inp >> (i*32);
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
  assert(databits%8==0);
    
  for(int j=0; j<databits/8; j++){
    unsigned char ot = (*signal)[j/4] >> ((j%4)*8);
    fputc(ot,file);
  }
}

// extract 32 bits of data, starting at bit 'startbit'
template<int N>
unsigned int getUintData( WData (*signal)[N], unsigned int startbit){
  int startWord = startbit/32;

  unsigned long tmp = (*signal)[startWord+1];
  tmp = tmp << 32;
  tmp |= (*signal)[startWord];
  tmp = tmp >> (startbit-startWord*32);

  return (unsigned int)(tmp);
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

void* readFile(char* filename, long* fsize){
  FILE *f = fopen(filename, "rb");
  if(f==NULL){ printf("Error, could not open file %s\n", filename); exit(1); }

  fseek(f, 0, SEEK_END);
  *fsize = ftell(f);
  fseek(f, 0, SEEK_SET);  //same as rewind(f);

  void *buf = malloc(*fsize);
  fread(buf, *fsize, 1, f);
  fclose(f);

  return buf;
}
