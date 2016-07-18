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
void init_camera(volatile Conf* conf, int camid) {
    write_cam_reg(conf, camid, CAM_DELAY); // delay
    printf("CAM1\n"); fflush(stdout);
    write_cam_reg(conf, camid, CAM_RESET); // Reset
    write_cam_reg(conf, camid, CAM_DELAY); // delay
    write_cam_safe(conf, camid, 0x1205);
    write_cam_safe(conf, camid, 0x1500);
    write_cam_safe(conf, camid, 0x0E80);
    write_cam_safe(conf, camid, 0x138F);
    write_cam_safe(conf, camid, 0x1300);
    write_cam_safe(conf, camid, 0x0000);// Gain (addr 00)
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

    if(argc!=1 && argc!=2){
        printf("Format: processimage <seconds>\n");
        exit(1);
    }

    int time = 0;
    if(argc==2) {
        time = atoi(argv[1]);
    }
    printf("HERE1"); fflush(stdout);

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

    printf("HERE2"); fflush(stdout);

    //unsigned lenInRaw;
    //FILE* imfile = openImage("/tmp/frame_128.raw", &lenInRaw);
    //printf("file LEN %d\n",lenInRaw);
    printf("framesize %d\n",frame_size);
    for(uint32_t i=0;i<frame_size*4*3; i++ ) {
        *(unsigned char*)(tribuf2_ptr+i)= i%256; 
    }
    printf("HERE3"); fflush(stdout);
    
    // mmap the device into memory 
    // This mmaps the control region (the MMIO for the control registers).
    void * gpioptr = mmap(NULL, page_size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, gpio_addr);
    if (gpioptr == MAP_FAILED) {
        printf("FAILED mmap for gpio_addr %x\n",gpio_addr);
        exit(1);
    }
   
    volatile Conf * conf = (Conf*) gpioptr;

    printf("HERE3\n"); fflush(stdout);
    // writes camera registers
    init_camera(conf,0);
    printf("HERE4\n"); fflush(stdout);
    init_camera(conf,1);
    printf("HERE5\n"); fflush(stdout);
    //check_cameras(conf);
    printf("Camera programmed!s\n");
    write_mmio(conf, MMIO_TRIBUF_ADDR(0), tribuf0_addr,1);
    write_mmio(conf, MMIO_FRAME_BYTES(0), frame_size,1);
    write_mmio(conf, MMIO_TRIBUF_ADDR(1), tribuf1_addr,1);
    write_mmio(conf, MMIO_FRAME_BYTES(1), frame_size,1);
    write_mmio(conf, MMIO_TRIBUF_ADDR(2), tribuf2_addr,1);
    write_mmio(conf, MMIO_FRAME_BYTES(2), frame_size*4,1);
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
            char outname0[17];
            char outname1[17];
            char outname2[17];
            sprintf(outname0,"/tmp/cam0_%.2d.raw",i/20);
            sprintf(outname1,"/tmp/cam1_%.2d.raw",i/20);
            sprintf(outname2,"/tmp/pipe_%.2d.raw",i/20);
            saveImage(outname0,tribuf0_ptr,frame_size);
            saveImage(outname1,tribuf1_ptr,frame_size);
            saveImage(outname2,tribuf2_ptr,frame_size*4);
        }
        printf("RUNNING STREAM  %d\n", time-i);
        fflush(stdout);
        sleep(1);
    }
    if(time==0) {
        char str[11];
        char cmd;
        unsigned int camid;
        unsigned int addr;
        unsigned int value;
        printf("Entering Interactive mode!\nCommands:\n");
        printf("\tCam reg read: r <camid> <addr>\n");
        printf("\tCam reg write: w <camid> <addr> <value>\n");
        printf("\tSave buffers: s\n");
        printf("\tDebug: d\n");
        printf("\tStop cmd: <Anything else>\n");
        fflush(stdout);
        while(1) {
            if(fgets(str,11,stdin)!=NULL) {
                if(sscanf(str,"%c %d %x %x",&cmd,&camid,&addr,&value)
                    && cmd=='w' && (camid==0||camid==1)) {
                    write_cam_safe(conf, camid, ((addr<<8) | value));
                    printf("WROTE 0x%.2x to addr 0x%.2x on CAM%d\n",value,addr,camid);
                }
                else if(sscanf(str,"%c %d %x",&cmd,&camid,&addr)
                        && cmd=='r' && (camid==0||camid==1)) {
                    value = read_cam_reg(conf,camid,addr);
                    printf("READ 0x%.2x from addr 0x%.2x on CAM%d\n",value,addr,camid);
                }
                else if(sscanf(str,"%c",&cmd) && cmd=='s') {
                    saveImage("/tmp/cam0.raw",tribuf0_ptr,frame_size);
                    saveImage("/tmp/cam1.raw",tribuf1_ptr,frame_size);
                    saveImage("/tmp/pipe.raw",tribuf2_ptr,frame_size*4);
                }
                else if(sscanf(str,"%c",&cmd) && cmd=='d') {
                    print_debug_regs(conf);
                }
                else {
                    printf("Bad CMD, stopping...\n");
                    fflush(stdout);
                    break;
                }
                fflush(stdout);
            }
            else {
                break;
            }
        }
    }
    write_mmio(conf, MMIO_CMD, CMD_STOP,1);
    printf("STOPPING STREAM\n");
    fflush(stdout);
    sleep(1);
  return 0;
}



