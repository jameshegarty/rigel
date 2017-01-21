local metadata = dofile(arg[1])
local outmodule = arg[2]

local outbytes = metadata.outputWidth*metadata.outputHeight*metadata.outputBytesPerPixel
local outpackets = outbytes/8 -- axi bus

print([=[#include <verilated.h>
#include <iostream>
#include "]=]..outmodule..[=[_verilator/V]=]..outmodule..[=[.h"

int main(int argc, char** argv) {
  //printf("START\n");
  Verilated::commandArgs(argc, argv); 

  //printf("alloc\n");
  V]=]..outmodule..[=[* top = new V]=]..outmodule..[=[;

  //vluint64_t cycle = 0;
  bool CLK = false;

  //printf("INIT\n");

  for(int i=0; i<100; i++){
    CLK = !CLK;
    top->process_input[0]=0;
    top->process_input[1]=0;
    top->process_input[2]=0;
    top->CLK = CLK;
    top->reset = true;
    top->ready_downstream = 1;
    top->eval();
  }

  //printf("read\n");

  FILE* infile = fopen("]=]..metadata.inputImage..[=[","rb");
  FILE* outfile = fopen("out/]=]..outmodule..[=[.verilator.raw","wb");

  if(infile==NULL){printf("could not open input\n");}
  if(outfile==NULL){printf("could not open output\n");}

  int validcnt = 0;

  //printf("do\n");
  while (!Verilated::gotFinish() && validcnt<]=]..outpackets..[=[) {
    if(CLK){
    if(top->ready){
      if(feof(infile)){
        top->process_input[2]=0;
      }else{
        top->process_input[2]=1;

        for(int j=0; j<2; j++){
          top->process_input[j]=0;
          for(int i=0; i<4; i++){
            unsigned long inp = fgetc(infile);
            //printf("INPUT %u %u\n",i,inp);
            top->process_input[j] |= (inp << i*8);
          }
          //printf("TINPUT %u\n",top->process_input[j]);
        }
      }
    }

    if(top->process_output[2]){
      //printf("VALIDDATA %d %u %u %u\n",validcnt,top->process_output[4], top->process_output[1], top->process_output[0]);
      validcnt++;
      //printf("OUTT %u\n",top->process_output[0]);
      for(int j=0; j<2; j++){
        for(int i=0; i<4; i++){
          unsigned char ot = top->process_output[j] >> (i*8);
          //printf("OUT %u %u\n",i,ot);
          fputc(ot,outfile);
        }
      }
    }
    }

    CLK = !CLK;

    top->CLK = CLK;
    top->ready_downstream = true;
    top->reset = false;
    top->eval();
  }

  top->final();
  delete top;
}
]=])