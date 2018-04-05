local R = require "rigel"
local RM = require "modules"
local S = require "systolic"
local types = require "types"
local J = require "common"
local types = require "types"
local SOC = {}

local PORTS = 4

--SOC.frameStart = R.newGlobal("frameStart","input", R.HandshakeTrigger,{nil,false})

--SOC.readAddrs = J.map(J.range(PORTS),function(i) return R.newGlobal("readAddr"..tostring(i),"output",R.Handshake(types.uint(32)),{0,false}) end)

--SOC.readData = J.map(J.range(PORTS),function(i) return R.newGlobal("readData"..tostring(i),"input",R.Handshake(types.bits(64))) end)

--SOC.writeAddrs = J.map(J.range(PORTS),function(i) return R.newGlobal("writeAddr"..tostring(i),"output",R.Handshake(types.uint(32)),{0,false}) end)
--SOC.writeData = J.map(J.range(PORTS),function(i) return R.newGlobal("writeData"..tostring(i),"output",R.Handshake(types.bits(64)),{0,false}) end)
  
-- does a 128 byte burst
-- uint25 addr -> bits(64)
SOC.axiBurstReadN = J.memoize(function(filename,Ntokens,port,X)
  J.err( type(port)=="number", "bulkRamRead: port must be number" )
  J.err( port>=0 and port<=PORTS,"bulkRamRead: port out of range" )

  local globals = {}
  globals[R.newGlobal("IP_MAXI"..port.."_ARADDR","output",R.Handshake(types.bits(32)))] = 1
  globals[R.newGlobal("IP_MAXI"..port.."_RDATA","input",R.Handshake(types.bits(64)))] = 1
  globals[R.newGlobal("IP_MAXI"..port.."_RRESP","input",types.bits(2))] = 1
  globals[R.newGlobal("IP_MAXI"..port.."_RLAST","input",types.bool())] = 1
  globals[R.newGlobal("IP_MAXI"..port.."_ARLEN","output",types.bits(4))] = 1
  globals[R.newGlobal("IP_MAXI"..port.."_ARSIZE","output",types.bits(2))] = 1
  globals[R.newGlobal("IP_MAXI"..port.."_ARBURST","output",types.bits(2))] = 1

  local globalMetadata = {}
  globalMetadata["MAXI"..port.."_read_filename"] = filename
  
  return RM.liftVerilog( "DRAMReader", R.HandshakeTrigger, R.Handshake(types.bits(64)),
[=[module DRAMReaderInner(
    //AXI port
    input ACLK,
    input ARESETN,
    output reg [31:0] M_AXI_ARADDR,
    input M_AXI_ARREADY,
    output  M_AXI_ARVALID,
    input [63:0] M_AXI_RDATA,
    output M_AXI_RREADY,
    input [1:0] M_AXI_RRESP,
    input M_AXI_RVALID,
    input M_AXI_RLAST,
    output [3:0] M_AXI_ARLEN,
    output [1:0] M_AXI_ARSIZE,
    output [1:0] M_AXI_ARBURST,
    
    //Control config
    input CONFIG_VALID,
    output CONFIG_READY,
    input [31:0] CONFIG_START_ADDR,
    input [31:0] CONFIG_NBYTES,
    
    //RAM port
    input DATA_READY_DOWNSTREAM,
    output DATA_VALID,
    output [63:0] DATA
);

assign M_AXI_ARLEN = 4'b1111;
assign M_AXI_ARSIZE = 2'b11;
assign M_AXI_ARBURST = 2'b01;
parameter IDLE = 0, RWAIT = 1;
    
//ADDR logic
reg [24:0] a_count;
reg a_state;  
assign M_AXI_ARVALID = (a_state == RWAIT);
always @(posedge ACLK) begin
    if (ARESETN == 0) begin
        a_state <= IDLE;
        M_AXI_ARADDR <= 0;
        a_count <= 0;
    end else case(a_state)
        IDLE: begin
            if(CONFIG_VALID) begin
                M_AXI_ARADDR <= CONFIG_START_ADDR;
                a_count <= CONFIG_NBYTES[31:7];
                a_state <= RWAIT;
            end
        end
        RWAIT: begin
            if (M_AXI_ARREADY == 1) begin
                if(a_count - 1 == 0)
                    a_state <= IDLE;
                a_count <= a_count - 1;
                M_AXI_ARADDR <= M_AXI_ARADDR + 128; // Bursts are 128 bytes long
            end
        end
    endcase
end
    
//READ logic
reg [31:0] b_count;
reg r_state;
assign M_AXI_RREADY = (r_state == RWAIT) && DATA_READY_DOWNSTREAM;
always @(posedge ACLK) begin
    if (ARESETN == 0) begin
        r_state <= IDLE;
        b_count <= 0;
    end else case(r_state)
        IDLE: begin
            if(CONFIG_VALID) begin
                b_count <= {CONFIG_NBYTES[31:7],7'b0}; // round to nearest 128 bytes
                r_state <= RWAIT;
            end
        end
        RWAIT: begin
            if (M_AXI_RVALID && DATA_READY_DOWNSTREAM) begin
                //use M_AXI_RDATA
                if(b_count - 8 == 0)
                    r_state <= IDLE;
                b_count <= b_count - 8; // each valid cycle the bus provides 8 bytes
            end
        end
    endcase
end

assign DATA = M_AXI_RDATA;
assign DATA_VALID = M_AXI_RVALID && (r_state == RWAIT);
assign CONFIG_READY = (r_state == IDLE) && (a_state == IDLE);

endmodule // DRAMReaderInner

module DRAMReader(
    //AXI port
    input CLK,
    input reset,

    output [32:0] IP_MAXI0_ARADDR,
    input IP_MAXI0_ARADDR_ready,

    input [64:0] IP_MAXI0_RDATA,
    output IP_MAXI0_RDATA_ready,

    input [1:0] IP_MAXI0_RRESP,

    input IP_MAXI0_RLAST,
    output [3:0] IP_MAXI0_ARLEN,
    output [1:0] IP_MAXI0_ARSIZE,
    output [1:0] IP_MAXI0_ARBURST,
    
    //Control config
    input process_input,
    output ready,
    
//    input [31:0] CONFIG_START_ADDR,
//    input [31:0] CONFIG_NBYTES,
    
    //RAM port
    input ready_downstream,
    output [64:0] process_output
    
);
parameter INSTANCE_NAME="inst";


DRAMReaderInner inner(
    //AXI port
    .ACLK(CLK),
    .ARESETN(~reset),

    .M_AXI_ARADDR(IP_MAXI0_ARADDR[31:0]),
    .M_AXI_ARREADY(IP_MAXI0_ARADDR_ready),
    .M_AXI_ARVALID(IP_MAXI0_ARADDR[32]),

    .M_AXI_RDATA(IP_MAXI0_RDATA[63:0]),
    .M_AXI_RREADY(IP_MAXI0_RDATA_ready),
    .M_AXI_RVALID(IP_MAXI0_RDATA[64]),

    .M_AXI_RRESP(IP_MAXI0_RRESP),

    .M_AXI_RLAST(IP_MAXI0_RLAST),
    .M_AXI_ARLEN(IP_MAXI0_ARLEN),
    .M_AXI_ARSIZE(IP_MAXI0_ARSIZE),
    .M_AXI_ARBURST(IP_MAXI0_ARBURST),
    
    //Control config
    .CONFIG_VALID(process_input),
    .CONFIG_READY(ready),
    .CONFIG_START_ADDR(32'h30008000),
    .CONFIG_NBYTES(32'd8192),
    
    //RAM port
    .DATA_READY_DOWNSTREAM(ready_downstream),
    .DATA_VALID(process_output[64]),
    .DATA(process_output[63:0])
);

endmodule
]=],globals,globalMetadata,{{1,1}},{{1,1}})
  
end)

SOC.axiBurstWriteN = J.memoize(function(filename,Ntokens,port,X)
  J.err( type(port)=="number", "bulkRamRead: port must be number" )
  J.err( port>=0 and port<=PORTS,"bulkRamRead: port out of range" )

  local globals = {}
  globals[R.newGlobal("IP_MAXI"..port.."_AWADDR","output",R.Handshake(types.bits(32)))] = 1
  globals[R.newGlobal("IP_MAXI"..port.."_WDATA","output",R.Handshake(types.bits(64)))] = 1
  globals[R.newGlobal("IP_MAXI"..port.."_WSTRB","output",types.bits(8))] = 1
  globals[R.newGlobal("IP_MAXI"..port.."_WLAST","output",types.bits(1))] = 1
  globals[R.newGlobal("IP_MAXI"..port.."_BRESP","input",R.Handshake(types.bits(2)))] = 1
  globals[R.newGlobal("IP_MAXI"..port.."_AWLEN","output",types.bits(4))] = 1
  globals[R.newGlobal("IP_MAXI"..port.."_AWSIZE","output",types.bits(2))] = 1
  globals[R.newGlobal("IP_MAXI"..port.."_AWBURST","output",types.bits(2))] = 1

  local globalMetadata = {}
  globalMetadata["MAXI"..port.."_write_filename"] = filename

  return RM.liftVerilog( "DRAMWriter", R.Handshake(types.bits(64)), R.HandshakeTrigger, 
[=[module DRAMWriterInner(
    //AXI port
    input ACLK,
    input ARESETN,
    output reg [31:0] M_AXI_AWADDR,
    input M_AXI_AWREADY,
    output M_AXI_AWVALID,
    
    output [63:0] M_AXI_WDATA,
    output [7:0] M_AXI_WSTRB,
    input M_AXI_WREADY,
    output M_AXI_WVALID,
    output M_AXI_WLAST,
    
    input [1:0] M_AXI_BRESP,
    input M_AXI_BVALID,
    output M_AXI_BREADY,
    
    output [3:0] M_AXI_AWLEN,
    output [1:0] M_AXI_AWSIZE,
    output [1:0] M_AXI_AWBURST,
    
    //Control config
    input CONFIG_VALID,
    output CONFIG_READY,
    input [31:0] CONFIG_START_ADDR,
    input [31:0] CONFIG_NBYTES,
    
    //RAM port
    input [63:0] DATA,
    output DATA_READY,
    input DATA_VALID

);

assign M_AXI_AWLEN = 4'b1111;
assign M_AXI_AWSIZE = 2'b11;
assign M_AXI_AWBURST = 2'b01;
assign M_AXI_WSTRB = 8'b11111111;

parameter IDLE = 0, RWAIT = 1;
    
//ADDR logic
reg [24:0] a_count;
reg a_state;  
assign M_AXI_AWVALID = (a_state == RWAIT);
always @(posedge ACLK) begin
    if (ARESETN == 0) begin
        a_state <= IDLE;
        M_AXI_AWADDR <= 0;
        a_count <= 0;
    end else case(a_state)
        IDLE: begin
            if(CONFIG_VALID) begin
                M_AXI_AWADDR <= CONFIG_START_ADDR;
                a_count <= CONFIG_NBYTES[31:7];
                a_state <= RWAIT;
            end
        end
        RWAIT: begin
            if (M_AXI_AWREADY == 1) begin
                if(a_count - 1 == 0)
                    a_state <= IDLE;
                a_count <= a_count - 1;
                M_AXI_AWADDR <= M_AXI_AWADDR + 128; 
            end
        end
    endcase
end

//WRITE logic
reg [31:0] b_count;
reg w_state;
always @(posedge ACLK) begin
    if (ARESETN == 0) begin
        w_state <= IDLE;
        b_count <= 0;
    end else case(w_state)
        IDLE: begin
            if(CONFIG_VALID) begin
                b_count <= {CONFIG_NBYTES[31:7],7'b0};
                w_state <= RWAIT;
                last_count <= 4'b1111;
            end
        end
        RWAIT: begin
            if (M_AXI_WREADY && M_AXI_WVALID) begin
                //use M_AXI_WDATA
                if(b_count - 8 == 0) begin
                    w_state <= IDLE;
                end
                last_count <= last_count - 4'b1;
                b_count <= b_count - 8;
            end
        end
    endcase
end

reg [3:0] last_count;
assign M_AXI_WLAST = last_count == 4'b0000;

assign M_AXI_WVALID = (w_state == RWAIT) && DATA_VALID;

assign DATA_READY = (w_state == RWAIT) && M_AXI_WREADY;
   
assign CONFIG_READY = (w_state == IDLE) && (a_state == IDLE);

assign M_AXI_BREADY = 1;

assign M_AXI_WDATA = DATA;

endmodule // DRAMWriter

module DRAMWriter(
    //AXI port
    input CLK,
    input reset,
    output reg [32:0] IP_MAXI0_AWADDR,
    input IP_MAXI0_AWADDR_ready,
    
    output [64:0] IP_MAXI0_WDATA,
    input IP_MAXI0_WDATA_ready,

    output [7:0] IP_MAXI0_WSTRB,
    output IP_MAXI0_WLAST,
    
    input [2:0] IP_MAXI0_BRESP,
    output IP_MAXI0_BRESP_ready,
    
    output [3:0] IP_MAXI0_AWLEN,
    output [1:0] IP_MAXI0_AWSIZE,
    output [1:0] IP_MAXI0_AWBURST,
    
    //Control config
//    input CONFIG_VALID,
//    output CONFIG_READY,
//    input [31:0] CONFIG_START_ADDR,
//    input [31:0] CONFIG_NBYTES,
    
    //RAM port
    input [64:0] process_input,
    output ready,

    output process_output,
    input ready_downstream
);
parameter INSTANCE_NAME="inst";

assign process_output=1'b0;

wire CONFIG_READY;

DRAMWriterInner inner(
    //AXI port
    .ACLK(CLK),
    .ARESETN(~reset),

    .M_AXI_AWADDR(IP_MAXI0_AWADDR[31:0]),
    .M_AXI_AWREADY(IP_MAXI0_AWADDR_ready),
    .M_AXI_AWVALID(IP_MAXI0_AWADDR[32]),
    
    .M_AXI_WDATA(IP_MAXI0_WDATA[63:0]),
    .M_AXI_WREADY(IP_MAXI0_WDATA_ready),
    .M_AXI_WVALID(IP_MAXI0_WDATA[64]),

    .M_AXI_BRESP(IP_MAXI0_BRESP[1:0]),
    .M_AXI_BVALID(IP_MAXI0_BRESP[2]),
    .M_AXI_BREADY(IP_MAXI0_BRESP_ready),

    .M_AXI_WSTRB(IP_MAXI0_WSTRB),
    .M_AXI_WLAST(IP_MAXI0_WLAST),
    .M_AXI_AWLEN(IP_MAXI0_AWLEN),
    .M_AXI_AWSIZE(IP_MAXI0_AWSIZE),
    .M_AXI_AWBURST(IP_MAXI0_AWBURST),
    
    //Control config
    .CONFIG_VALID(~reset),
    .CONFIG_READY(CONFIG_READY),
    .CONFIG_START_ADDR(32'h3000A000),
    .CONFIG_NBYTES(32'd8192),
    
    //RAM port
    .DATA(process_input[63:0]),
    .DATA_READY(ready),
    .DATA_VALID(process_input[64])
);

endmodule

]=],globals, globalMetadata,{{1,1}},{{1,1}})
  
end)

-- {Handshake(uint25),Handshake(bits(64))}
-- you need to write 16 data chunks per address!!
SOC.bulkRamWrite = J.memoize(function(port)
  err( type(port)=="number", "bulkRamWrite: port must be number" )
  err( port>0 and port<=PORTS,"bulkRamWrite: port out of range" )

  local H = require "rigelhll"
  local brri = R.input(types.tuple{ R.Handshake(types.uint(25)), R.Handshake(types.bits(64)) } )
  local addr = brri:selectStream(0)
  local addr = H.liftSystolic(function(i) return S.lshift(S.cast(i,H.u32),S.constant(7,H.u8)) end)(addr)
  local datai = brri:selectStream(1)

  local pipelines = R.statements{ R.writeGlobal( "datawrite", SOC.writeData[port], datai ), R.writeGlobal( "addrwrite", SOC.writeAddrs[port], addr )  }

  local BRR =  RM.lambda( "bulkRamWrite_"..tostring(port), brri, pipelines )

  return BRR
end)

SOC.readScanline = J.memoize(function(filename,W,H,ty)
  local fs = R.readGlobal("framestartread",SOC.frameStart)

  local totalBytes = W*H*ty:verilogBits()/8
  err( totalBytes % 128 == 0,"NYI - non burst aligned reads")

  local addr = R.apply("addr",RM.counter(types.uint(25),totalBytes/128),fs)
  local out = R.apply("ramRead", SOC.bulkRamRead(1), addr )

  local EC = 1024*16
  out = R.apply("underflow_US", RM.underflow( types.bits(64), totalBytes/8, EC, true ), out)

  local HLL = require "rigelhll"
  out = HLL.cast(ty)(out)
  
  return RM.lambda("readScanline",nil,out)
end)

SOC.writeScanline = J.memoize(function(filename,W,H,ty)
  local I = R.input(R.Handshake(ty))

  local totalBytes = W*H*ty:verilogBits()/8
  err( totalBytes % 128 == 0,"NYI - non burst aligned reads")
  local outputCount = totalBytes/8

  local EC = 1024*16
  ----------------
  local out = R.apply("overflow", RM.liftHandshake(RM.liftDecimate(RM.overflow(R.extractData(hsfn.outputType), outputCount))), I)
  out = R.apply("underflow", RM.underflow(R.extractData(hsfn.outputType), totalBytes/8, EC, false ), out)
  out = R.apply("cycleCounter", RM.cycleCounter(R.extractData(hsfn.outputType), totalBytes/8 ), out)

  local HLL = require "rigelhll"
  out = HLL.cast(types.bits(64))(out)
  
  ---------------
  local fs = R.readGlobal("framestartread",SOC.frameStart)

  local totalBytes = W*H*ty:verilogBits()/8
  err( totalBytes % 128 == 0,"NYI - non burst aligned write")

  local addr = R.apply("addr",RM.counter(types.uint(25),totalBytes/128),fs)
  ---------------
  
  out = R.apply("write", SOC.bulkRamWrite(1), R.concat("w",{addr,out}) )
  
  return RM.lambda("writeScanline",I,out)
end)

function SOC.export(t)
  if t==nil then t=_G end
  for k,v in pairs(SOC) do rawset(t,k,v) end
end


return SOC
