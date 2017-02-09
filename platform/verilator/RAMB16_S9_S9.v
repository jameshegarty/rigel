module RAMB16_S9_S9(
  input WEA,
  input ENA,
  input SSRA,
  input CLKA,
  input [10:0] ADDRA,
  input [7:0] DIA,
  input DIPA,
//  output [3:0] DOPA,
  output [7:0] DOA,
  input WEB,
  input ENB,
  input SSRB,
  input CLKB,
  input [10:0] ADDRB,
  input [7:0] DIB,
  input DIPB,
//  output [3:0] DOPB,
  output [7:0] DOB);
  parameter WRITE_MODE_A = "write_first";
  parameter WRITE_MODE_B = "write_first";

  reg [7:0] ram [1024:0];
  reg [7:0] bufferA;
  reg [7:0] bufferB;

  assign DOA = bufferA;
  assign DOB = bufferB;

//  assign DOPA = 4'b0;
//  assign DOPB = 4'b0;

  always @(posedge CLKA or posedge CLKB) begin

    if( CLKA && CLKB && ENA && ENB && WEA && WEB ) begin
      if(ADDRA==ADDRB) begin
        $display("ERROR: write to some address on both ports");
      end else begin
        // different address: OK
        bufferA <= ram[ADDRA];
        bufferB <= ram[ADDRB];
        ram[ADDRA] <= DIA;
        ram[ADDRB] <= DIB;
      end
    end else begin
      // not writing on both ports: can treat A/B differently
      
      if (CLKA && ENA) begin
        if (WEA) begin
          ram[ADDRA] <= DIA;
          bufferA <= ram[ADDRA];
        end else begin
          bufferA <= ram[ADDRA];
        end
      end

      if (CLKB && ENB) begin
        if (WEB) begin
          ram[ADDRB] <= DIB;
          bufferB <= ram[ADDRB];
        end else begin
          bufferB <= ram[ADDRB];
        end
      end

    end

  end



endmodule