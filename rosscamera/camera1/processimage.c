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
#include "processimagelib.h"

void init_camera(volatile Conf* conf) {
    write_cam_reg(conf, CAM_DELAY); // delay
    write_cam_reg(conf, CAM_RESET); // Reset
    write_cam_reg(conf, CAM_DELAY); // delay
    write_cam_safe(conf,0x1205);
    //write_cam_safe(conf,0x1180);
    write_cam_safe(conf,0x1500);
    write_cam_safe(conf,0x0E80);
    write_cam_reg(conf, CAM_DELAY); // delay
    write_cam_reg(conf, CAM_DELAY); // delay
}

int main(int argc, char *argv[]) {
    unsigned gpio_addr = 0x70000000;
    uint32_t frame_size = 640*480;
    
    unsigned tribuf0_addr = 0x30008000;
    int tribuf0_size = frame_size * 3;
    
    unsigned  tribuf1_addr = tribuf0_addr + tribuf0_size;
    int tribuf1_size = frame_size*4 *3;
    
    unsigned page_size = sysconf(_SC_PAGESIZE);
    
    char* raw_name= "/tmp/out.raw";
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
        printf("FAILED mmap for vgabuf %x\n",tribuf1_addr);
        exit(1);
    }
    //unsigned lenInRaw;
    //FILE* imfile = openImage("/tmp/frame_128.raw", &lenInRaw);
    //printf("file LEN %d\n",lenInRaw);
    printf("framesize %d\n",frame_size);
    for(uint32_t i=0;i<frame_size; i++ ) {
        *(unsigned char*)(tribuf1_ptr+i)= 0; 
    }
    for(uint32_t i=0;i<frame_size; i++ ) {
        *(unsigned char*)(tribuf1_ptr+frame_size+i)= 128; 
    }
    for(uint32_t i=0;i<frame_size; i++ ) {
        *(unsigned char*)(tribuf1_ptr+2*frame_size+i)= 255; 
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
    init_camera(conf);
    printf("Camera programmed!s\n");
    write_mmio(conf, MMIO_TRIBUF_ADDR(0), tribuf0_addr,1);
    write_mmio(conf, MMIO_FRAME_BYTES(0), frame_size,1);
    write_mmio(conf, MMIO_TRIBUF_ADDR(1), tribuf1_addr,1);
    write_mmio(conf, MMIO_FRAME_BYTES(1), frame_size*4,1);
    print_debug_regs(conf);
    printf("WAIT 3s\n");
    fflush(stdout);
    // Start stream
    printf("START STREAM\n");
    fflush(stdout);
    //print_debug_regs(conf);
    write_mmio(conf, MMIO_CMD, CMD_START,1);
    int time = 20;
    for (int i=0; i<time;i++) {
        printf("RUNNING STREAM  %d\n", time-i);
        print_debug_regs(conf);
        fflush(stdout);
        sleep(1);
    }
    saveImage(raw_name,tribuf0_ptr,frame_size);
    write_mmio(conf, MMIO_CMD, CMD_STOP,1);
    printf("STOPPING STREAM\n");
    fflush(stdout);
    sleep(1);
    print_debug_regs(conf);
    fflush(stdout);
  return 0;
}



