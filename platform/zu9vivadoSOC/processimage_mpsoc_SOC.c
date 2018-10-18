/*
 * This test application is to read/write data directly from/to the device 
 * from userspace. 
 * 
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <assert.h>
#include <stdbool.h>

#include <sys/time.h>

double CurrentTimeInSeconds() {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return tv.tv_sec + tv.tv_usec / 1000000.0;
}

void usage(void) {
	printf("*argv[0] -g <GPIO_ADDRESS> -i|-o <VALUE>\n");
	printf("    -g <GPIO_ADDR>   GPIO physical address\n");
	printf("    -i               Input from GPIO\n");
	printf("    -o <VALUE>       Output to GPIO\n");
	return;
}

typedef struct {
    unsigned int start;
    unsigned int done;
  //    unsigned int dest;
  //    unsigned int len;
} Conf;

FILE* openImage(char* filename, int* numbytes){
  FILE* infile = fopen(filename, "rb");
  if(infile==NULL){
    printf("File not found %s\n",filename);
    exit(1);
  }
  fseek(infile, 0L, SEEK_END);
  *numbytes = ftell(infile);
  fseek(infile, 0L, SEEK_SET);

  return infile;
}

void loadImage(FILE* infile,  volatile void* address, int numbytes){
  int outlen = fread(address, sizeof(char), numbytes, infile);
  if(outlen!=numbytes){
    printf("ERROR READING\n");
  }

  fclose(infile);
}

bool isPowerOf2(unsigned int x) {
  return x && !(x & (x - 1));
}

// we don't have a standard library... so reimplement this badly
unsigned int mylog2(unsigned int x){
  printf("mylog2\n");
  unsigned int res = 0;
  // find highest true bit
  while(x=x>>1){printf("H%d\n",x);res++;}
  return res;
}

int saveImage(char* filename,  volatile void* address, int numbytes){
  FILE* outfile = fopen(filename, "wb");
  if(outfile==NULL){
    printf("could not open for writing %s\n",filename);
    exit(1);
  }
  int outlen = fwrite(address,1,numbytes,outfile);
  if(outlen!=numbytes){
    printf("ERROR WRITING\n");
  }

  fclose(outfile);
}

void configureHPC64bit(int fd, off_t offset){
  // set RDCTRL (AFIFM) register bits 1:0 to 1, to set HPC0 (aka SAXIGP0 on PS8) to 64 bit mode
  // See "Xilinx register map"
  // https://www.xilinx.com/html_docs/registers/ug1087/ug1087-zynq-ultrascale-registers.html
  void * CTRL = mmap(NULL, 32, PROT_READ|PROT_WRITE, MAP_SHARED, fd, offset);
  if(CTRL==(void *) -1){
    printf("Error mmaping CTRL\n");
    exit(1);
  }

  printf("@RDCTRL: %08x\n", *(unsigned int*)(CTRL));
  *(unsigned int*)CTRL = 1;
  printf("@RDCTRL: %08x\n", *(unsigned int*)(CTRL));
  //  printf("@CTRL: %08x\n", *(unsigned int*)(CTRL));
  fflush(stdout);
  
  //  void * WRCTRL = mmap(NULL, 4, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0xFD360014);
  //  if(WRCTRL==(void *) -1){
  //    printf("Error mmaping WRCTRL\n");
  //    exit(1);
  //  }

  // set WRCTRL (AFIFM) register bits [1:0] to 1, to set HPC0 (aka SAXIGP0 on PS8) to 64 bit mode
  printf("@WRCTRL: %08x\n", *((unsigned int*)(CTRL)+(0x14/4)));
  *((unsigned int*)(CTRL)+(0x14/4)) = 0x3b1;
  printf("@WRCTRL: %08x\n", *((unsigned int*)(CTRL)+(0x14/4)));
  
  //  *(unsigned int*)WRCTRL = 1;
  //  printf("@WRCTRL: %08x\n", *(unsigned int*)(WRCTRL));
  fflush(stdout);

  munmap(CTRL,32);
}

void configureBusses(int fd){
  configureHPC64bit( fd, 0xFD360000 ); // HPC0 aka SAXIGP0
  configureHPC64bit( fd, 0xFD370000 ); // HPC1 aka SAXIGP1

  /////////////////////////////////////////////////////////////////////////////////////////////////////
  // set afi_fs (FPD_SLCR) register bits [9:8] to 0, to set HPM0 (aka MAXIGP0 on PS8) to 32 bit mode
  void * ptr_axi = mmap(NULL, 0x6000, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0xFD610000);
  printf("@ptr: %08x\n", *((unsigned int*)(ptr_axi)+(0x5000/4)));
  fflush(stdout);
  *((unsigned int*)(ptr_axi)+(0x5000/4)) = 0;

  printf("@ptr: %08x\n", *((unsigned int*)(ptr_axi)+(0x5000/4)));
  fflush(stdout);

}

int loadInputs(int fd, char *argv[], void* ptr){
  printf("Load Inputs\n");
  fflush(stdout);
    
  int MEMBASE = strtol(argv[2],NULL,16);
  int curArg = 4;
  
  if(strcmp(argv[curArg],"--inputs")!=0){
    //std::cout << "fourth argument should be '--inputs' but is " <<  << std::endl;
    printf("fourth argument should be '--inputs' but is %s\n",argv[curArg]);
    fflush(stdout);
    exit(1);
  }else{
    curArg++;
  }

  int inputCount=1;
  while(strcmp(argv[curArg],"--registers")!=0){
    unsigned int addr = strtol(argv[curArg+1],NULL,16);
    unsigned int addrOffset = addr-MEMBASE;
    
    FILE* infile = fopen(argv[curArg],"rb");
    if(infile==NULL){
      printf("could not open input '%s'\n", argv[curArg]);
      fflush(stdout);
      exit(1);
    }
    fseek(infile, 0L, SEEK_END);
    unsigned long insize = ftell(infile);
    fseek(infile, 0L, SEEK_SET);
    fread( ptr+addrOffset, insize, 1, infile );
    fclose( infile );
    
    //std::cout << "Input File " << inputCount << ": filename=" << argv[curArg] << " address=0x" << std::hex << addr << " addressOffset=0x" << addrOffset << std::dec << " bytes=" << insize <<std::endl;
    printf("Input File %d: filename=%s address=0x%x addressOffset=0x%x bytes=%d\n",inputCount, argv[curArg],addr,addrOffset,insize);
    fflush(stdout);
      
    inputCount++;
    curArg+=2;
  }

  return curArg;
}

int setRegisters(int curArg, char *argv[], void* ptr, unsigned int GPIO_BASE){
  printf("Set Registers\n");
  fflush(stdout);

  curArg++; // for "--registers"
  while(strcmp(argv[curArg],"--outputs")!=0){
    printf("PARSE Reg %s %s\n",argv[curArg],argv[curArg+1]);
    fflush(stdout);
  
    unsigned int addr = strtol(argv[curArg],NULL,16);
    int bytes = strlen(argv[curArg+1])/2;
    printf("Set Register %x withNBytes %d, GPIO_BASE %x\n",addr,bytes,GPIO_BASE);
    fflush(stdout);
  
    //unsigned int* data = (unsigned int*)argv[curArg+1];
    char tmp[9]="";

    for(int i=0; i<bytes/4; i++){
      for(int j=0; j<8; j++){
        tmp[j] = argv[curArg+1][i*8+j];
      }

      printf("STR %s\n",tmp);
      fflush(stdout);
      unsigned int data = strtoul(tmp,NULL,16);
      printf("try to Set Reg %x\n",data);
      fflush(stdout);

      unsigned int offset = addr+i*4-GPIO_BASE;
      printf("offset %d\n",offset);
      fflush(stdout);
      
      *(unsigned int*)(ptr+offset) = data;
      //setReg( top, verbose, addr+i*4, data);
    }

    curArg+=2;
  }

  return curArg;
}

int writeOutputs(int curArg, int argc, char *argv[], void* ptr){
  printf("Write Outputs\n");
  fflush(stdout);
      
  int MEMBASE = strtol(argv[2],NULL,16);
  
  curArg++; // for "--outputs"
  unsigned int outputCount = 0;
  while(curArg<argc){
    printf("HERE\n");
    fflush(stdout);
          
    unsigned int addr = strtol(argv[curArg+1],NULL,16);
    unsigned int addrOffset = addr-MEMBASE;

    unsigned int w = atoi(argv[curArg+2]);
    unsigned int h = atoi(argv[curArg+3]);
    unsigned int bitsPerPixel = atoi(argv[curArg+4]);

    if( bitsPerPixel%8!=0 ){
      printf("Error, bits per pixel not byte aligned!\n");
      fflush(stdout);
      exit(1);
    }

    unsigned int bytes = w*h*(bitsPerPixel/8);

    //char outFilename[100];
    //sprintf(outFilename,"%s.verilatorSOC.raw",argv[curArg]);
    char *outFilename = "out.raw";

    //addrOffset=0;
    //bytes=8192*3;
    
    //std::cout << "Output File " << outputCount << ": filename=" << outFilename << " address=0x" << std::hex << addr << " addressOffset=0x" << addrOffset << std::dec << " W=" << w <<" H="<<h<<" bitsPerPixel="<<bitsPerPixel<<" bytes="<<bytes<<std::endl;
    printf("Output File %d: filename=%s address=0x%x addressOffset=0x%x bytes=%d\n",outputCount,outFilename,addr,addrOffset,bytes);
    fflush(stdout);
      
    FILE* outfile = fopen(outFilename,"wb");
    if(outfile==NULL){
      printf("could not open output '%s'\n", outFilename);
      fflush(stdout);
      exit(1);
    }
    fwrite( ptr+addrOffset, bytes, 1, outfile);
    fclose(outfile);

    curArg+=5;
    outputCount++;
  }

}

int main(int argc, char *argv[]) {
	unsigned int gpio_addr = strtol(argv[1],NULL,16);

  printf("start processimage SOC\n");
  fflush(stdout);
    
	unsigned int page_size = sysconf(_SC_PAGESIZE);

	printf("GPIO access through /dev/mem. addr:%08x page_size:%d\n", gpio_addr, page_size);
  fflush(stdout);
  
	if (gpio_addr == 0) {
		printf("GPIO physical address is required.\n");
		usage();
		return -1;
	}
	
	int fd = open ("/dev/mem", O_RDWR | O_SYNC );
	if (fd < 1) {
    printf("Error opening /dev/mem\n");
		perror(argv[0]);
		return -1;
  }

  configureBusses(fd);

  int MEMBASE = strtol(argv[2],NULL,16);
  int MEMSIZE = strtol(argv[3],NULL,16)-MEMBASE;

  printf("MEMBASE: %x MEMSIZE: %x\n", MEMBASE, MEMSIZE);
  
  void * ptr = mmap(NULL, MEMSIZE, PROT_READ|PROT_WRITE, MAP_SHARED, fd, MEMBASE);
  if(ptr==(void *) -1){
    printf("Error mmaping\n");
    exit(1);
  }

  // mmap the device into memory 
  // This mmaps the control region (the MMIO for the control registers).
  // Image data is located at addr 'copy_addr'
  // HACK: just map 1MB of GPIO space
  void * gpioptr = mmap(NULL, sizeof(Conf), PROT_READ|PROT_WRITE, MAP_SHARED, fd, gpio_addr);
  
  if(gpioptr==(void *) -1){
    printf("Error mmaping gpio\n");
    exit(1);
  }

  // this sleep is needed for the z100, but not the z20
  sleep(2);

  volatile Conf * conf = (Conf*) gpioptr;
  volatile unsigned int* taps = ((unsigned int*) gpioptr)+(sizeof(Conf)/sizeof(unsigned int));

  int curArg;
  
  for(int round=0; round<2; round++){
    printf("Round %d. setting gpio and clearning mem\n",round);
    fflush(stdout);

    for(int i=0; i<MEMSIZE; i+=4){ *(unsigned int*)(ptr+i)=0x0df0adba; }
    curArg = loadInputs( fd, argv, ptr );
    curArg = setRegisters( curArg, argv, gpioptr, gpio_addr );
 
    printf("conf: start: %d, done: %d\n", conf->start, conf->done);
    fflush(stdout);
    
    conf->start = 0;
    conf->done = 0;
  
    // HACK: poking cmd causes the pipeline to start. sleep for 2sec to make sure the above registers set before starting.
    sleep(2);
    printf("conf: start: %d, done: %d\n", conf->start, conf->done);
    fflush(stdout);

    double startTime = CurrentTimeInSeconds();
    conf->start = 1;
    printf("conf: start: %d, done: %d\n", conf->start, conf->done);
    fflush(stdout);
    
    //usleep(10000);
    
    unsigned long interval = 10;
    
    bool doneBitSet = false;
    double doneTime = 0.f;
    for(unsigned long t=0; t<1000000*8; t+=interval){
      //printf("%d conf: cmd: %d, src: %08x, dest: %08x, len: %d\n", t, conf->cmd, conf->src, conf->dest, conf->len);
      //sleep(8); // this sleep needs to be 2 for the z100, but 1 for the z20
      
      if(conf->done>0 && doneTime==0.f){
        doneTime = CurrentTimeInSeconds();
        doneBitSet=true;
        break;
      }
      
      usleep(interval);
    }
    
    if(doneBitSet==false){
      printf("ERROR: done bit was not set at end of time! Writing out outputs anyway...\n");
    }else{
      float MHZ = 100.f;
      float HZ = 1000000.f;
      double len = doneTime-startTime;
      printf("Done after %f seconds, %f cycles (@ %f MHZ)\n", len, (MHZ*HZ)*len,MHZ);
    }
  }
  
  writeOutputs(curArg,argc,argv,ptr);

  printf("conf: start: %d, done: %d\n", conf->start, conf->done);
  fflush(stdout);

  munmap( gpioptr, page_size );
  munmap( ptr, MEMSIZE );

  return 0;
}


