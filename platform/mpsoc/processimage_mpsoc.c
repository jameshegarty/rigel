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

void usage(void) {
	printf("*argv[0] -g <GPIO_ADDRESS> -i|-o <VALUE>\n");
	printf("    -g <GPIO_ADDR>   GPIO physical address\n");
	printf("    -i               Input from GPIO\n");
	printf("    -o <VALUE>       Output to GPIO\n");
	return;
}

typedef struct {
    int cmd;
    int src;
    int dest;
    unsigned int len;
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

int main(int argc, char *argv[]) {
	unsigned gpio_addr = strtol(argv[1],NULL,16);
	unsigned copy_addr = strtol(argv[2],NULL,16);
  



  printf("start processimage\n");
  fflush(stdout);
    
  if(argc!=11){
    printf("ERROR: insufficient args. Should be: gpio_addr_hex src_addr_hex inputFilename outputFilename inputW inputH inputBitsPerPixel outputW outH outputBitsPerPixel\n");
    exit(1);
  }



  unsigned int inputW = atoi(argv[5]);
  unsigned int inputH = atoi(argv[6]);
  unsigned int inputBitsPerPixel = atoi(argv[7]);

  unsigned int outputW = atoi(argv[8]);
  unsigned int outputH = atoi(argv[9]);
  unsigned int outputBitsPerPixel = atoi(argv[10]);

  if(outputBitsPerPixel%8!=0){
    printf("Error, NYI - non-byte aligned output bits per pixel not supported!\n");
    exit(1);
  }

  unsigned int outputBytesPerPixel = outputBitsPerPixel/8;

	unsigned page_size = sysconf(_SC_PAGESIZE);

	printf("GPIO access through /dev/mem. addr:%08x page_size:%d\n", gpio_addr, page_size);
  fflush(stdout);
  
	if (gpio_addr == 0) {
		printf("GPIO physical address is required.\n");
		usage();
		return -1;
	}
	
	int fd = open ("/dev/mem", O_RDWR | O_SYNC );
	if (fd < 1) {
		perror(argv[0]);
		return -1;
  }

  // set RDCTRL (AFIFM) register bits 1:0 to 1, to set HPC0 (aka SAXIGP0 on PS8) to 64 bit mode
  // See "Xilinx register map"
  // https://www.xilinx.com/html_docs/registers/ug1087/ug1087-zynq-ultrascale-registers.html
  void * CTRL = mmap(NULL, 32, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0xFD360000);
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

  // set afi_fs (FPD_SLCR) register bits [9:8] to 0, to set HPM0 (aka MAXIGP0 on PS8) to 32 bit mode
  void * ptr_axi = mmap(NULL, 0x6000, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0xFD610000);
  printf("@ptr: %08x\n", *((unsigned int*)(ptr_axi)+(0x5000/4)));
  fflush(stdout);
  *((unsigned int*)(ptr_axi)+(0x5000/4)) = 0;

  printf("@ptr: %08x\n", *((unsigned int*)(ptr_axi)+(0x5000/4)));
  fflush(stdout);

  unsigned lenInRaw;
  FILE* imfile = openImage(argv[3], &lenInRaw);
  printf("file LEN %d\n",lenInRaw);
  fflush(stdout);
    
  unsigned int lenIn = lenInRaw;
  // include extra axi burst of cycle count
  unsigned int lenOutRaw = outputW*outputH*outputBytesPerPixel+128;
  unsigned int lenOut = lenOutRaw;

  // HW pads to next largest axi burst size (128 bytes)
  if (lenIn%(8*16)!=0){
    lenIn = lenInRaw + (8*16-(lenInRaw % (8*16)));
  }

  if (lenOutRaw%(8*16)!=0){
    lenOut = lenOutRaw + (8*16-(lenOutRaw % (8*16)));
  }

  printf("LENOUT %d, LENOUTRAW:%d\n", lenOut,lenOutRaw);
  assert(lenIn % (8*16) == 0);
  printf("LENIN %d\n",lenIn);
  assert(lenOut % (8*16) == 0);

  printf("mapping image addr %08x\n",copy_addr);
  fflush(stdout);
    
  void * ptr = mmap(NULL, lenIn+lenOut, PROT_READ|PROT_WRITE, MAP_SHARED, fd, copy_addr);
  if(ptr==(void *) -1){
    printf("Error mmaping\n");
    exit(1);
  }

  loadImage( imfile, ptr, lenInRaw );

  // zero out the output region
  for(int i=0; i<lenOut; i++){ *(unsigned char*)(ptr+lenIn+i)=0; }


  // mmap the device into memory 
  // This mmaps the control region (the MMIO for the control registers).
  // Image data is located at addr 'copy_addr'
  void * gpioptr = mmap(NULL, page_size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, gpio_addr);
  if(gpioptr==(void *) -1){
    printf("Error mmaping gpio\n");
    exit(1);
  }
  
  // this sleep is needed for the z100, but not the z20
  sleep(2);

  volatile Conf * conf = (Conf*) gpioptr;

  printf("setting gpio\n");
  fflush(stdout);
  printf("conf: cmd: %d, src: %08x, dest: %08x, len: %d\n", conf->cmd, conf->src, conf->dest, conf->len);
  fflush(stdout);
  
  conf->src = copy_addr;
  conf->dest = copy_addr + lenIn;
  conf->len = lenIn;

  // HACK: poking cmd causes the pipeline to start. sleep for 2sec to make sure the above registers set before starting.
  sleep(2);
  conf->cmd = 3;
  printf("conf: cmd: %d, src: %08x, dest: %08x, len: %d\n", conf->cmd, conf->src, conf->dest, conf->len);
  fflush(stdout);

  //usleep(10000);
  sleep(2); // this sleep needs to be 2 for the z100, but 1 for the z20

  saveImage(argv[4],ptr+lenIn,lenOutRaw);
  //  saveImage(argv[4],ptr,lenOutRaw);

  printf("conf: cmd: %d, src: %08x, dest: %08x, len: %d\n", conf->cmd, conf->src, conf->dest, conf->len);
  fflush(stdout);

  munmap( gpioptr, page_size );
  munmap( ptr, lenIn+lenOut );

  return 0;
}


