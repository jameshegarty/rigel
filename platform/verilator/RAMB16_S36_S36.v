module RAMB16_S36_S36(
  input WEA,
  input ENA,
  input SSRA,
  input CLKA,
  input [8:0] ADDRA,
  input [31:0] DIA,
  input [3:0] DIPA,
//  output [3:0] DOPA,
  output [31:0] DOA,
  input WEB,
  input ENB,
  input SSRB,
  input CLKB,
  input [8:0] ADDRB,
  input [31:0] DIB,
  input [3:0] DIPB,
//  output [3:0] DOPB,
  output [31:0] DOB);
  parameter WRITE_MODE_A = "write_first";
  parameter WRITE_MODE_B = "write_first";

  reg [31:0] ram [256:0];
  reg [31:0] bufferA;
  reg [31:0] bufferB;

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