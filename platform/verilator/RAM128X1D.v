module RAM128X1D(WCLK,D,WE,SPO,DPO,A,DPRA);
   input      WCLK; //write clock
   input      D; // write data input
   input      WE; // write enable
   output     SPO; // R/W port addressed by A
   output     DPO; // R port addressed by DPRA
   input [6:0] A; // R/W port address
   input [6:0] DPRA; // R port address
   
   reg [127:0] ram;

   assign DPO = ram[DPRA];
   assign SPO=D;

   always @(posedge WCLK) begin
      if(WE) begin
         ram[A] <= D;
      end
   end



endmodule
