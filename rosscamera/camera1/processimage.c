/*
 * This test application is to read/write data directly from/to the device 
 * from userspace. 
 * 
 */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <assert.h>
#include <stdbool.h>

#define MMIO_SIZE 16
#define MMIO_CMD 0
#define MMIO_STREAMBUF_NBYTES 1
#define MMIO_STREAMBUF_ADDR 2
#define MMIO_STATUS 3
#define MMIO_DEBUG0 4
#define MMIO_DEBUG1 5
#define MMIO_DEBUG2 6
#define MMIO_DEBUG3 7
#define MMIO_CAM_CMD 8
#define MMIO_CAM_RESP 9
#define MMIO_CAM_RESP_CNT 10

#define CAM_DELAY 0xF0F0
#define CAM_RESET 0x1280

typedef struct {
    uint32_t mmio[MMIO_SIZE];
} Conf;


void write_mmio(volatile Conf* conf, int offset, uint32_t data) {
    printf("MMIO WRITE: 0x%x to offset %x\n",data,offset);
    conf->mmio[offset] = data;
}

uint32_t read_mmio(volatile Conf* conf, int offset) {
    uint32_t data = conf->mmio[offset];
    printf("MMIO READ: 0x%x from addr %x\n",data,offset);
    return data;
}

void poll_mmio(volatile Conf* conf, int offset, uint32_t val) {
    uint32_t data;
    do {
        //data = conf->mmio[offset];
        data = read_mmio(conf,offset);
    } while (data != val);
}

void print_debug_regs(volatile Conf* conf) {
    read_mmio(conf, MMIO_DEBUG0);
    read_mmio(conf, MMIO_DEBUG1);
    read_mmio(conf, MMIO_DEBUG2);
    read_mmio(conf, MMIO_DEBUG3);
}

// cam_data should contain the cam addr in the lowest byte
uint32_t read_cam_reg(volatile Conf* conf, uint32_t cam_data) {

    //cam data should only contain 8 bits
    if (cam_data & 0xFFFFFF00) {
        printf("Bad cam addr! needs to be 1 byte");
        exit(1);
    }
    cam_data = (cam_data<<8); //bit 16 needs to be 0
    uint32_t cam_resp_cnt = read_mmio(conf, MMIO_CAM_RESP_CNT);
    printf("cam_resp_cnt=%d",cam_resp_cnt);
    write_mmio(conf,MMIO_CAM_CMD, cam_data);
    // Wait for response (CAM_RESP_CNT will increment
    poll_mmio(conf, MMIO_CAM_RESP_CNT, cam_resp_cnt+1);
    uint32_t cam_resp = read_mmio(conf, MMIO_CAM_RESP);
    //Error checking
    // first 16:8 bits should be the same as cam_data;
    if ((cam_data & 0x0001FF00)!=(cam_resp & 0x0001FF00)) {
        printf("cam response is not the same as cam_data!!\n");
        exit(1);
    }
    //check that the error is not set
    if ((cam_data & 0x00020000) != (cam_resp & 0x00020000) ) {
        printf("Cam response reports an error! Did you write before checking the response??\n");
        exit(1);
    }
    return (cam_resp & 0x000000FF);
}

void write_cam_reg(volatile Conf* conf, uint32_t cam_data) {
    //cam data should only contain 16 bits
    if (cam_data & 0xFFFF0000) {
        printf("Bad cam reg data! %x should be 1byte addr, 1byte data",cam_data);
        exit(1);
    }
    cam_data |= 0x10000; //bit 16 is the write cmd
    uint32_t cam_resp_cnt = read_mmio(conf, MMIO_CAM_RESP_CNT);
    printf("cam_resp_cnt=%d",cam_resp_cnt);
    write_mmio(conf,MMIO_CAM_CMD, cam_data);
    // Wait for response (CAM_RESP_CNT will increment
    poll_mmio(conf, MMIO_CAM_RESP_CNT, cam_resp_cnt+1);
    uint32_t cam_resp = read_mmio(conf, MMIO_CAM_RESP);
    //Error checking
    // first 16 bits should be the same as cam_data;
    if ((cam_data & 0x0001FFFF)!=(cam_resp & 0x0001FFFF)) {
        printf("cam response is not the same as cam_data!!\n");
        exit(1);
    }
    //check that the error is not set
    if ((cam_data & 0x00020000) != (cam_resp & 0x00020000) ) {
        printf("Cam response reports an error! Did you write before checking the response??\n");
        exit(1);
    }
}

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
char* ppmheader = "P6 640 480 255 ";
int header_len;
int saveImagePPM(char* filename,  volatile void* address, int numbytes){
    FILE* outfile = fopen(filename, "wb");
    if(outfile==NULL){
        printf("could not open for writing %s\n",filename);
        exit(1);
    }
    //write header
    int headerlen = printf("%s",ppmheader);
    int outlen = fwrite(ppmheader, 1, headerlen, outfile);
    if(outlen!=headerlen) {
        printf("ERROR HEADER, %d, %d\n", outlen, headerlen);
    }
    for (int n=0; n<numbytes; n++) {
        for (int i=0; i<3; i++) {
            outlen = fwrite(address+3*n+i,1,1,outfile);
            if(outlen!=numbytes){
                printf("ERROR WRITING\n");
                exit(0);
            }
       }
    }

    fclose(outfile);
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
    printf("Saving image %s, at address %p, with numbytes %d, bytes written %d\n",filename,address, numbytes,outlen);
    fclose(outfile);
}

void init_camera(volatile Conf* conf) {
    write_cam_reg(conf, 0x1280); // Reset
    write_cam_reg(conf, 0xF0F0); // delay

    write_cam_reg(conf, 0x1180); // external pclk
    uint32_t rd = read_cam_reg(conf, 0x11); // external pclk
    if (rd != 0x80) {
        printf("Bad read value for 0x11\n");
        printf("read=%x, expect=%x\n",rd,0x80);
    }
    write_cam_reg(conf, 0xF0F0); // delay
    write_cam_reg(conf, 0xF0F0); // delay
}

int main(int argc, char *argv[]) {
    unsigned gpio_addr = 0x70000000;
    unsigned stream_addr = 0x30008000;
    uint32_t frame_size = 640*480;
    int streambuf_size = frame_size * 8;
    unsigned page_size = sysconf(_SC_PAGESIZE);
    
    char* raw_name= "/tmp/out.raw";
    char* ppm_name = "out.ppm";
    
    printf("GPIO access through /dev/mem. %d\n", page_size);

    int fd = open ("/dev/mem", O_RDWR);
    if (fd < 1) {
        perror(argv[0]);
        return -1;
    }

    printf("mapping %08x\n",stream_addr);
    void * stream_ptr = mmap(NULL, streambuf_size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, stream_addr);
    if (stream_ptr == MAP_FAILED) {
        printf("FAILED mmap for streamaddr %x\n",stream_addr);
        exit(1);
    }
    
    // mmap the device into memory 
    // This mmaps the control region (the MMIO for the control registers).
    void * gpioptr = mmap(NULL, page_size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, gpio_addr);
    if (gpioptr == MAP_FAILED) {
        printf("FAILED mmap for gpio_addr %x\n",gpio_addr);
        exit(1);
    }
   
    volatile Conf * conf = (Conf*) gpioptr;
    
    
    write_mmio(conf, MMIO_STREAMBUF_ADDR, stream_addr);
    write_mmio(conf, MMIO_STREAMBUF_NBYTES, frame_size*4);
    print_debug_regs(conf);

    // writes camera registers
    
    printf("Camera programmed!s\n");
    init_camera(conf);
    
    printf("WAIT 1s\n");
    sleep(1);
    // Start stream
    printf("START STREAM\n");
    write_mmio(conf, MMIO_CMD, 0x5);
    printf("WAIT 5s\n");
    sleep(2);
    print_debug_regs(conf);
    //write_mmio(conf, MMIO_CMD, 0x9);
    
    saveImage(raw_name,stream_ptr,frame_size);
    //saveImagePPM(ppm_name,ptr,frame_size);


  return 0;
}



