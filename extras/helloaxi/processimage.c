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

unsigned int mylog2(unsigned int x){
  printf("mylog2\n");
  unsigned int res = 0;
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
	unsigned gpio_addr = 0x70000000;
	unsigned copy_addr = atoi(argv[1]);

  if(argc!=6){
    printf("ERROR< insufficient args\n");
  }

  unsigned int downsampleX = atoi(argv[4]);
  unsigned int downsampleY = atoi(argv[5]);
  unsigned int downsample = downsampleX*downsampleY;
  unsigned int downsampleShift = mylog2(downsample);
  printf("DSX %d DSY %d DS %d DSS %d\n",downsampleX,downsampleY,downsample,downsampleShift);

	unsigned page_size = sysconf(_SC_PAGESIZE);

	printf("GPIO access through /dev/mem. %d\n", page_size);

	if (gpio_addr == 0) {
		printf("GPIO physical address is required.\n");
		usage();
		return -1;
	}
	
	int fd = open ("/dev/mem", O_RDWR);
	if (fd < 1) {
		perror(argv[0]);
		return -1;
  }

  unsigned lenRaw;
  FILE* imfile = openImage(argv[2], &lenRaw);
  printf("file LEN %d\n",lenRaw);

  // we pad out the length to 128 bytes as required, but just leave it filled with garbage
  unsigned lenRawDown = lenRaw/downsample;
  unsigned int lenDown = lenRawDown + (8*16-(lenRawDown % (8*16)));
  //unsigned int lenDown = lenRawDown;
  printf("LENDOWN %d\n", lenDown);
  unsigned int len = lenDown*downsample;
  assert(len % (8*16) == 0);
  printf("LEN %d\n",len);
  assert((len/(downsample)) % (8*16) == 0);

  printf("mapping %08x\n",copy_addr);
  void * ptr = mmap(NULL, 2*len, PROT_READ|PROT_WRITE, MAP_SHARED, fd, copy_addr);

  loadImage( imfile, ptr, lenRaw );
  //memset(ptr+len,0,len);
  for(int i=0; i<len; i++){ *(unsigned char*)(ptr+len+i)=0; }
  //saveImage("before.raw",ptr,len);

  // mmap the device into memory 
  void * gpioptr = mmap(NULL, page_size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, gpio_addr);
  
  volatile Conf * conf = (Conf*) gpioptr;


  conf->src = copy_addr;
  conf->dest = copy_addr + len;
  unsigned int lenPacked = len | (downsampleShift << 29);
  printf("LEN PACKED %d\n",lenPacked);
  conf->len = lenPacked;
  conf->cmd = 3;

  //usleep(10000);
  sleep(1);

  saveImage(argv[3],ptr+len,lenRaw);
  //saveImage(argv[3],ptr,lenRaw);

  return 0;
}


