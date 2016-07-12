/*
 * This test application is to read/write data directly from/to the device 
 * from userspace. 
 * 
 */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <assert.h>
#include <stdbool.h>
#include "processimagelib.h"



void check_cameras(volatile Conf* conf) {
    for (uint32_t i=0; i<255; i++) {
        uint32_t cam0 = read_cam_reg(conf,0,i);
        uint32_t cam1 = read_cam_reg(conf,1,i);
        if (cam0 != cam1) {
            printf("ERROR: 0x%.2x, (cam0,cam1)=(0x%.2x,0x%.2x)\n",i,cam0,cam1);
        }
    }


}
void init_camera(volatile Conf* conf, int camid, int gain) {
    write_cam_reg(conf, camid, CAM_DELAY); // delay
    write_cam_reg(conf, camid, CAM_RESET); // Reset
    write_cam_reg(conf, camid, CAM_DELAY); // delay
    write_cam_safe(conf, camid, 0x1205);
    write_cam_safe(conf, camid, 0x1500);
    write_cam_safe(conf, camid, 0x0E80);
    write_cam_safe(conf, camid, 0x138F);
    write_cam_safe(conf, camid, 0x1300);
    write_cam_safe(conf, camid, 0x0000+gain);// Gain (addr 00)
    write_cam_safe(conf, camid, 0x01C0); // White Balance
    write_cam_safe(conf, camid, 0x02C0); // White Balance
    write_cam_safe(conf, camid, 0x0718); // Auto Exposure
    write_cam_safe(conf, camid, 0x1000);
    write_cam_safe(conf, camid, 0x0400);
 


    write_cam_safe(conf, camid, 0x2080); //offset
    write_cam_safe(conf, camid, 0x2180); //offset
    write_cam_safe(conf, camid, 0x2280); //offset
    write_cam_safe(conf, camid, 0x2380); //offset
    
    write_cam_safe(conf, camid, 0x0580); //avg B
    write_cam_safe(conf, camid, 0x0680); //avg G
    write_cam_safe(conf, camid, 0x0880); //avg R


    write_cam_reg(conf, camid, CAM_DELAY); // delay
    write_cam_reg(conf, camid, CAM_DELAY); // delay
}

int main(int argc, char *argv[]) {

    if(argc!=3){
        printf("Format: processimage seconds gain\n");
        printf("gain:0-127\n");
        exit(1);
    }

    int time = atoi(argv[1]);
    int gain = atoi(argv[2]);

    if(gain < 0 || gain >127){
      printf("gain:0-127\n");
      exit(1);
    }

    unsigned gpio_addr = 0x70000000;
    uint32_t frame_size = 640*480;
    
    unsigned tribuf0_addr = 0x30008000;
    int tribuf0_size = frame_size*3;
    
    unsigned  tribuf1_addr = tribuf0_addr + tribuf0_size;
    int tribuf1_size = frame_size*3;
    
    unsigned  tribuf2_addr = tribuf1_addr + tribuf1_size;
    int tribuf2_size = frame_size*4*3;
    
    unsigned page_size = sysconf(_SC_PAGESIZE);
    
    char* raw_name0= "/tmp/cam0.raw";
    char* raw_name1= "/tmp/cam1.raw";
    char* pix_name= "/tmp/outpix.raw";
    char* ppm_name = "out.ppm";
    
    printf("GPIO access through /dev/mem. %d\n", page_size);

    int fd = open ("/dev/mem", O_RDWR);
    if (fd < 1) {
        perror(argv[0]);
        return -1;
    }

    printf("mapping %08x\n",tribuf0_addr);
    void * tribuf0_ptr = mmap(NULL, tribuf0_size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, tribuf0_addr);
    if (tribuf0_ptr == MAP_FAILED) {
        printf("FAILED mmap for tribuf0 %x\n",tribuf0_addr);
        exit(1);
    }
    void * tribuf1_ptr = mmap(NULL, tribuf1_size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, tribuf1_addr);
    if (tribuf1_ptr == MAP_FAILED) {
        printf("FAILED mmap for tribuf1 %x\n",tribuf1_addr);
        exit(1);
    }
    void * tribuf2_ptr = mmap(NULL, tribuf2_size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, tribuf2_addr);
    if (tribuf2_ptr == MAP_FAILED) {
        printf("FAILED mmap for tribuf2 %x\n",tribuf2_addr);
        exit(1);
    }
    //unsigned lenInRaw;
    //FILE* imfile = openImage("/tmp/frame_128.raw", &lenInRaw);
    //printf("file LEN %d\n",lenInRaw);
    printf("framesize %d\n",frame_size);
    for(uint32_t i=0;i<frame_size*4*3; i++ ) {
        *(unsigned char*)(tribuf2_ptr+i)= 128; 
    }

    // mmap the device into memory 
    // This mmaps the control region (the MMIO for the control registers).
    void * gpioptr = mmap(NULL, page_size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, gpio_addr);
    if (gpioptr == MAP_FAILED) {
        printf("FAILED mmap for gpio_addr %x\n",gpio_addr);
        exit(1);
    }
   
    volatile Conf * conf = (Conf*) gpioptr;

    // writes camera registers
    init_camera(conf,0,gain);
    init_camera(conf,1,gain);
    //check_cameras(conf);
    printf("Camera programmed!s\n");
    write_mmio(conf, MMIO_TRIBUF_ADDR(0), tribuf0_addr,1);
    write_mmio(conf, MMIO_FRAME_BYTES(0), frame_size,1);
    write_mmio(conf, MMIO_TRIBUF_ADDR(1), tribuf1_addr,1);
    write_mmio(conf, MMIO_FRAME_BYTES(1), frame_size,1);
    write_mmio(conf, MMIO_TRIBUF_ADDR(2), tribuf2_addr,1);
    write_mmio(conf, MMIO_FRAME_BYTES(2), frame_size*4,1);
    read_mmio(conf, MMIO_TRIBUF_ADDR(0), 1);
    read_mmio(conf, MMIO_FRAME_BYTES(0), 1);
    read_mmio(conf, MMIO_TRIBUF_ADDR(1), 1);
    read_mmio(conf, MMIO_FRAME_BYTES(1), 1);
    read_mmio(conf, MMIO_TRIBUF_ADDR(2), 1);
    read_mmio(conf, MMIO_FRAME_BYTES(2), 1);
   
    print_debug_regs(conf);
    printf("WAIT 3s\n");
    fflush(stdout);
    // Start stream
    printf("START STREAM\n");
    fflush(stdout);
    write_mmio(conf, MMIO_CMD, CMD_START,1);

    for (int i=time; i>0;i--) {
        if(i%20==2) {
            printf("HOLD STILL!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
        }
        if(i%20==1) {
            char outname0[16];
            char outname1[16];
            sprintf(outname0,"/tmp/cam0_%d.raw",i/20);
            sprintf(outname1,"/tmp/cam1_%d.raw",i/20);
            saveImage(outname0,tribuf0_ptr,frame_size);
            saveImage(outname1,tribuf1_ptr,frame_size);
        }

        
        printf("RUNNING STREAM  %d\n", time-i);
        //print_debug_regs(conf);
        fflush(stdout);
        sleep(1);
    }
    //saveImage(raw_name0,tribuf0_ptr,frame_size);
    //saveImage(raw_name1,tribuf1_ptr,frame_size);
    //saveImage(pix_name,tribuf2_ptr,frame_size*4);
    write_mmio(conf, MMIO_CMD, CMD_STOP,1);
    printf("STOPPING STREAM\n");
    fflush(stdout);
    sleep(1);
    print_debug_regs(conf);
    fflush(stdout);
  return 0;
}



