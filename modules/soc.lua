local R = require "rigel"
local RM = require "modules"
local S = require "systolic"
local types = require "types"
local J = require "common"
local types = require "types"
local SOC = {}

SOC.ports = 4
SOC.currentMAXIReadPort = 0
SOC.currentMAXIWritePort = 0
SOC.currentAddr = 0x30008000

--SOC.frameStart = R.newGlobal("frameStart","input", R.HandshakeTrigger,{nil,false})

--SOC.readAddrs = J.map(J.range(PORTS),function(i) return R.newGlobal("readAddr"..tostring(i),"output",R.Handshake(types.uint(32)),{0,false}) end)

--SOC.readData = J.map(J.range(PORTS),function(i) return R.newGlobal("readData"..tostring(i),"input",R.Handshake(types.bits(64))) end)

--SOC.writeAddrs = J.map(J.range(PORTS),function(i) return R.newGlobal("writeAddr"..tostring(i),"output",R.Handshake(types.uint(32)),{0,false}) end)
--SOC.writeData = J.map(J.range(PORTS),function(i) return R.newGlobal("writeData"..tostring(i),"output",R.Handshake(types.bits(64)),{0,false}) end)
  
-- does a 128 byte burst
-- uint25 addr -> bits(64)
SOC.axiBurstReadN = J.memoize(function(filename,Nbytes,port,address,X)
  J.err( type(port)=="number", "axiBurstReadN: port must be number" )
  J.err( port>=0 and port<=SOC.ports,"axiBurstReadN: port out of range" )
  J.err( type(Nbytes)=="number","axiBurstReadN: Nbytes must be number" )
  J.err( Nbytes % 128 == 0, "AxiBurstReadN: Nbytes must have 128 as a factor" )
  J.err( type(address)=="number","axiBurstReadN: missing address")
  J.err( X==nil, "axiBurstReadN: too many arguments" )

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

  local ModuleName = J.sanitize("DRAMReader_"..tostring(Nbytes).."_"..tostring(port).."_"..tostring(address))
  
  return RM.liftVerilog( ModuleName, R.HandshakeTrigger, R.Handshake(types.bits(64)),
[=[module ]=]..ModuleName..[=[_inner(
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

module ]=]..ModuleName..[=[(
    //AXI port
    input CLK,
    input reset,

    output [32:0] IP_MAXI]=]..port..[=[_ARADDR,
    input IP_MAXI]=]..port..[=[_ARADDR_ready,

    input [64:0] IP_MAXI]=]..port..[=[_RDATA,
    output IP_MAXI]=]..port..[=[_RDATA_ready,

    input [1:0] IP_MAXI]=]..port..[=[_RRESP,

    input IP_MAXI]=]..port..[=[_RLAST,
    output [3:0] IP_MAXI]=]..port..[=[_ARLEN,
    output [1:0] IP_MAXI]=]..port..[=[_ARSIZE,
    output [1:0] IP_MAXI]=]..port..[=[_ARBURST,
    
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


]=]..ModuleName..[=[_inner inner(
    //AXI port
    .ACLK(CLK),
    .ARESETN(~reset),

    .M_AXI_ARADDR(IP_MAXI]=]..port..[=[_ARADDR[31:0]),
    .M_AXI_ARREADY(IP_MAXI]=]..port..[=[_ARADDR_ready),
    .M_AXI_ARVALID(IP_MAXI]=]..port..[=[_ARADDR[32]),

    .M_AXI_RDATA(IP_MAXI]=]..port..[=[_RDATA[63:0]),
    .M_AXI_RREADY(IP_MAXI]=]..port..[=[_RDATA_ready),
    .M_AXI_RVALID(IP_MAXI]=]..port..[=[_RDATA[64]),

    .M_AXI_RRESP(IP_MAXI]=]..port..[=[_RRESP),

    .M_AXI_RLAST(IP_MAXI]=]..port..[=[_RLAST),
    .M_AXI_ARLEN(IP_MAXI]=]..port..[=[_ARLEN),
    .M_AXI_ARSIZE(IP_MAXI]=]..port..[=[_ARSIZE),
    .M_AXI_ARBURST(IP_MAXI]=]..port..[=[_ARBURST),
    
    //Control config
    .CONFIG_VALID(process_input),
    .CONFIG_READY(ready),
    .CONFIG_START_ADDR(32'h]=]..string.format('%x',address)..[=[),
    .CONFIG_NBYTES(32'd]=]..Nbytes..[=[),
    
    //RAM port
    .DATA_READY_DOWNSTREAM(ready_downstream),
    .DATA_VALID(process_output[64]),
    .DATA(process_output[63:0])
);

endmodule
]=],globals,globalMetadata,{{1,1}},{{1,1}})
  
end)

SOC.axiBurstWriteN = J.memoize(function(filename,Nbytes,port,address,X)
  J.err( type(filename)=="string","axiBurstWriteN: filename must be string")
  J.err( type(port)=="number", "axiBurstWriteN: port must be number" )
  J.err( port>=0 and port<=SOC.ports,"axiBurstWriteN: port out of range" )
  J.err( type(Nbytes)=="number","axiBurstWriteN: Nbytes must be number")
  J.err( type(address)=="number","axiBurstWriteN: missing address")
  J.err( X==nil, "axiBurstWriteN: too many arguments" )
  
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
    output reg [32:0] IP_MAXI]=]..port..[=[_AWADDR,
    input IP_MAXI]=]..port..[=[_AWADDR_ready,
    
    output [64:0] IP_MAXI]=]..port..[=[_WDATA,
    input IP_MAXI]=]..port..[=[_WDATA_ready,

    output [7:0] IP_MAXI]=]..port..[=[_WSTRB,
    output IP_MAXI]=]..port..[=[_WLAST,
    
    input [2:0] IP_MAXI]=]..port..[=[_BRESP,
    output IP_MAXI]=]..port..[=[_BRESP_ready,
    
    output [3:0] IP_MAXI]=]..port..[=[_AWLEN,
    output [1:0] IP_MAXI]=]..port..[=[_AWSIZE,
    output [1:0] IP_MAXI]=]..port..[=[_AWBURST,
    
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

reg HACK = 1'b1;

// HACK: to drive CONFIG_VALID, wait until we are not in reset, and DRAMWriterInner has accepted CONFIG_VALID
// (this will happen once it sets ready=true). Then set CONFIG_VALID to false to keep it from writing multiple times
always @(posedge CLK) begin
  if(reset==1'b0 && ready) begin
    HACK=1'b0;
  end
end

DRAMWriterInner inner(
    //AXI port
    .ACLK(CLK),
    .ARESETN(~reset),

    .M_AXI_AWADDR(IP_MAXI]=]..port..[=[_AWADDR[31:0]),
    .M_AXI_AWREADY(IP_MAXI]=]..port..[=[_AWADDR_ready),
    .M_AXI_AWVALID(IP_MAXI]=]..port..[=[_AWADDR[32]),
    
    .M_AXI_WDATA(IP_MAXI]=]..port..[=[_WDATA[63:0]),
    .M_AXI_WREADY(IP_MAXI]=]..port..[=[_WDATA_ready),
    .M_AXI_WVALID(IP_MAXI]=]..port..[=[_WDATA[64]),

    .M_AXI_BRESP(IP_MAXI]=]..port..[=[_BRESP[1:0]),
    .M_AXI_BVALID(IP_MAXI]=]..port..[=[_BRESP[2]),
    .M_AXI_BREADY(IP_MAXI]=]..port..[=[_BRESP_ready),

    .M_AXI_WSTRB(IP_MAXI]=]..port..[=[_WSTRB),
    .M_AXI_WLAST(IP_MAXI]=]..port..[=[_WLAST),
    .M_AXI_AWLEN(IP_MAXI]=]..port..[=[_AWLEN),
    .M_AXI_AWSIZE(IP_MAXI]=]..port..[=[_AWSIZE),
    .M_AXI_AWBURST(IP_MAXI]=]..port..[=[_AWBURST),
    
    //Control config
    .CONFIG_VALID(HACK),
    .CONFIG_READY(CONFIG_READY),
    .CONFIG_START_ADDR(32'h]=]..string.format('%x',address)..[=[),
    .CONFIG_NBYTES(32'd]=]..Nbytes..[=[),
    
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

SOC.readBurst = J.memoize(function(filename,W,H,ty,V,X)
  J.err( type(filename)=="string","readBurst: filename must be string")
  J.err( type(W)=="number", "readBurst: W must be number")
  J.err( type(H)=="number", "readBurst: H must be number")
  J.err( types.isType(ty), "readBurst: type must be type")
  J.err(ty:verilogBits()%8==0,"NYI - readBurst currently required byte-aligned data")
  local nbytes = W*H*(ty:verilogBits()/8)
  J.err( nbytes%128==0,"NYI - readBurst requires 128 aligned size" )
  J.err( V==nil or type(V)=="number", "readBurst: V must be number or nil")
  if V==nil then V=1 end
  J.err(X==nil, "readBurst: too many arguments")
  
  local globalMetadata={}
  globalMetadata["MAXI"..SOC.currentMAXIReadPort.."_read_W"] = W
  globalMetadata["MAXI"..SOC.currentMAXIReadPort.."_read_H"] = H
  globalMetadata["MAXI"..SOC.currentMAXIReadPort.."_read_V"] = V
  globalMetadata["MAXI"..SOC.currentMAXIReadPort.."_read_type"] = tostring(ty)
  globalMetadata["MAXI"..SOC.currentMAXIReadPort.."_read_bitsPerPixel"] = ty:verilogBits()
  globalMetadata["MAXI"..SOC.currentMAXIReadPort.."_read_address"] = SOC.currentAddr
  
  local inp = R.input(R.HandshakeTrigger)
  local res = RM.lambda("ReadBurst_W"..W.."_H"..H.."_v"..V.."_port"..SOC.currentMAXIReadPort.."_addr"..SOC.currentAddr.."_"..tostring(ty),inp,SOC.axiBurstReadN(filename,nbytes,SOC.currentMAXIReadPort,SOC.currentAddr)(inp),nil,nil,nil,globalMetadata)

  SOC.currentMAXIReadPort = SOC.currentMAXIReadPort+1
  SOC.currentAddr = SOC.currentAddr+nbytes

  return res
end)

SOC.writeBurst = J.memoize(function(filename,W,H,ty,V,X)
  J.err( type(filename)=="string","writeBurst: filename must be string")
  J.err( type(W)=="number", "writeBurst: W must be number")
  J.err( type(H)=="number", "writeBurst: H must be number")
  J.err( types.isType(ty), "writeBurst: type must be type")
  J.err(ty:verilogBits()%8==0,"NYI - writeBurst currently required byte-aligned data")
  local nbytes = W*H*(ty:verilogBits()/8)
  J.err( nbytes%128==0,"NYI - writeBurst requires 128 aligned size" )
  J.err( V==nil or type(V)=="number", "writeBurst: V must be number or nil")
  if V==nil then V=1 end
  J.err(X==nil, "writeBurst: too many arguments")
  
  local globalMetadata={}
  globalMetadata["MAXI"..SOC.currentMAXIWritePort.."_write_W"] = W
  globalMetadata["MAXI"..SOC.currentMAXIWritePort.."_write_H"] = H
  globalMetadata["MAXI"..SOC.currentMAXIWritePort.."_write_V"] = V
  globalMetadata["MAXI"..SOC.currentMAXIWritePort.."_write_type"] = tostring(ty)
  globalMetadata["MAXI"..SOC.currentMAXIWritePort.."_write_bitsPerPixel"] = ty:verilogBits()
  globalMetadata["MAXI"..SOC.currentMAXIWritePort.."_write_address"] = SOC.currentAddr
  
  local inp = R.input(R.Handshake(types.bits(64)))
  local res = RM.lambda("WriteBurst_W"..W.."_H"..H.."_v"..V.."_port"..SOC.currentMAXIWritePort.."_addr"..SOC.currentAddr.."_"..tostring(ty),inp,SOC.axiBurstWriteN(filename,nbytes,SOC.currentMAXIWritePort,SOC.currentAddr)(inp),nil,nil,nil,globalMetadata)

  SOC.currentMAXIWritePort = SOC.currentMAXIWritePort+1
  SOC.currentAddr = SOC.currentAddr+nbytes

  return res
end)


function SOC.export(t)
  if t==nil then t=_G end
  for k,v in pairs(SOC) do rawset(t,k,v) end
end


return SOC
