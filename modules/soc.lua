local R = require "rigel"
local RM = require "modules"
local S = require "systolic"
local types = require "types"
local J = require "common"
local types = require "types"
local C = require "examplescommon"
local SDF = require "sdfrate"

local SOCMT

if terralib~=nil then
  SOCMT = require("socTerra")
end

local SOC = {}

SOC.ports = 4
SOC.currentMAXIReadPort = 0
SOC.currentMAXIWritePort = 0
SOC.currentSAXIPort = 0
SOC.currentAddr = 0x30008000
SOC.currentRegAddr = 0xA0000008 -- first 8 bytes are start/done bit

SOC.axiRegs = J.memoize(function(tab,port)

  if port==nil then
    port = SOC.currentSAXIPort
    SOC.currentSAXIPort = SOC.currentSAXIPort + 1
  end

  local globalMetadata = {}
  local globals = {}

  local addToModuleHack = {}
  local regPorts = ""
  local regPortAssigns = ""
  local NREG = 2
  local curDataBit = 64 -- for start/done
  for k,v in pairs(tab) do
    J.err( type(k)=="string", "axiRegs: key must be string" )
    J.err( types.isType(v[1]), "axiRegs: first key must be type" )
    J.err( v[1]:toCPUType()==v[1], "axiRegs: NYI - input type must be a CPU type" )
    J.err( v[1]:verilogBits()<32 or v[1]:verilogBits()%32==0, "axiRegs: NYI - input type must be 32bit aligned")
    v[1]:checkLuaValue(v[2])

    NREG = NREG + math.max(v[1]:verilogBits()/32,1)

    assert(v[1]:verilogBits()%4==0) -- for hex
    globalMetadata["Register_"..string.format("%x",SOC.currentRegAddr)] = v[1]:valueToHex(v[2])
    globalMetadata["AddrOfRegister_"..k] = SOC.currentRegAddr
    globalMetadata["TypeOfRegister_"..k] = v[1]
    
    regPortAssigns = regPortAssigns.."assign "..k.." = CONFIG_DATA["..(curDataBit+v[1]:verilogBits()-1)..":"..curDataBit.."];\n"

    SOC.currentRegAddr = SOC.currentRegAddr + math.ceil(v[1]:verilogBits()/32)*4
    curDataBit = curDataBit + math.max(v[1]:verilogBits(),32)

    print("ADD GLOBAL",k)
    globals[R.newGlobal(k,"output",v[1])] = 1
    addToModuleHack[k] = R.newGlobal(k,"input",v[1])

    regPorts = regPorts.."output ["..tostring(v[1]:verilogBits()-1)..":0] "..k..[[,
]]
  end

  globals[R.newGlobal("IP_SAXI"..port.."_ARADDR","input",R.Handshake(types.bits(32)))] = 1
  globals[R.newGlobal("IP_SAXI"..port.."_AWADDR","input",R.Handshake(types.bits(32)))] = 1
  globals[R.newGlobal("IP_SAXI"..port.."_RDATA","output",R.Handshake(types.bits(32)))] = 1
  globals[R.newGlobal("IP_SAXI"..port.."_WDATA","input",R.Handshake(types.bits(32)))] = 1
  globals[R.newGlobal("IP_SAXI"..port.."_BRESP","output",R.Handshake(types.bits(2)))] = 1
  
  globals[R.newGlobal("IP_SAXI"..port.."_ARID","input",types.bits(12))] = 1
  globals[R.newGlobal("IP_SAXI"..port.."_AWID","input",types.bits(12))] = 1
  globals[R.newGlobal("IP_SAXI"..port.."_BID","output",types.bits(12))] = 1
  globals[R.newGlobal("IP_SAXI"..port.."_RID","output",types.bits(12))] = 1
  globals[R.newGlobal("IP_SAXI"..port.."_RLAST","output",types.bool())] = 1
  globals[R.newGlobal("IP_SAXI"..port.."_RRESP","output",types.bits(2))] = 1
  globals[R.newGlobal("IP_SAXI"..port.."_WSTRB","input",types.bits(4))] = 1

  local ModuleName = J.sanitize("Regs_"..tostring(tab).."_"..tostring(port))

  local REG_ADDR_BITS = math.ceil(math.log(NREG)/math.log(2))

  local verbose = false
  
--  local res = RM.liftVerilog( ModuleName, R.HandshakeTrigger, R.HandshakeTrigger,
local vstring = {[=[
module ict106_axilite_conv #
  (
   parameter integer C_AXI_ID_WIDTH              = 12,
   parameter integer C_AXI_ADDR_WIDTH            = 32,
   parameter integer C_AXI_DATA_WIDTH            = 32 // CONSTANT
   )
  (
   // System Signals
   input  wire                          ACLK,
   input  wire                          ARESETN,
   input  wire [C_AXI_ID_WIDTH-1:0]     S_AXI_AWID,
   input  wire [C_AXI_ADDR_WIDTH-1:0]   S_AXI_AWADDR,
   input  wire                          S_AXI_AWVALID,
   output wire                          S_AXI_AWREADY,
   input  wire [C_AXI_DATA_WIDTH-1:0]   S_AXI_WDATA,
   input  wire [C_AXI_DATA_WIDTH/8-1:0] S_AXI_WSTRB,
   input  wire                          S_AXI_WVALID,
   output wire                          S_AXI_WREADY,
   output wire [C_AXI_ID_WIDTH-1:0]     S_AXI_BID,
   output wire [2-1:0]                  S_AXI_BRESP,
   output wire                          S_AXI_BVALID,
   input  wire                          S_AXI_BREADY,
   input  wire [C_AXI_ID_WIDTH-1:0]     S_AXI_ARID,
   input  wire [C_AXI_ADDR_WIDTH-1:0]   S_AXI_ARADDR,
   input  wire                          S_AXI_ARVALID,
   output wire                          S_AXI_ARREADY,
   output wire [C_AXI_ID_WIDTH-1:0]     S_AXI_RID,
   output wire [C_AXI_DATA_WIDTH-1:0]   S_AXI_RDATA,
   output wire [2-1:0]                  S_AXI_RRESP,
   output wire                          S_AXI_RLAST,    // Constant =1
   output wire                          S_AXI_RVALID,
   input  wire                          S_AXI_RREADY,
   output wire [C_AXI_ADDR_WIDTH-1:0]   M_AXI_AWADDR,
   output wire                          M_AXI_AWVALID,
   input  wire                          M_AXI_AWREADY,
   output wire [C_AXI_DATA_WIDTH-1:0]   M_AXI_WDATA,
   output wire [C_AXI_DATA_WIDTH/8-1:0] M_AXI_WSTRB,
   output wire                          M_AXI_WVALID,
   input  wire                          M_AXI_WREADY,
   input  wire [2-1:0]                  M_AXI_BRESP,
   input  wire                          M_AXI_BVALID,
   output wire                          M_AXI_BREADY,
   output wire [C_AXI_ADDR_WIDTH-1:0]   M_AXI_ARADDR,
   output wire                          M_AXI_ARVALID,
   input  wire                          M_AXI_ARREADY,
   input  wire [C_AXI_DATA_WIDTH-1:0]   M_AXI_RDATA,
   input  wire [2-1:0]                  M_AXI_RRESP,
   input  wire                          M_AXI_RVALID,
   output wire                          M_AXI_RREADY
  );
  
  wire [31:0] m_axaddr;

  // Arbiter
  reg read_active;
  reg write_active;
  reg busy;

  wire read_req;
  wire write_req;
  wire read_complete;
  wire write_complete;
  
  reg [1:0] areset_d; // Reset delay register
  always @(posedge ACLK) begin
    areset_d <= {areset_d[0], ~ARESETN};
  end
  
  assign read_req  = S_AXI_ARVALID & ~write_active & ~busy & ~|areset_d;
  assign write_req = (S_AXI_AWVALID & ~read_active & ~busy & ~S_AXI_ARVALID & ~|areset_d) | (write_active & ~busy);

  assign read_complete  = M_AXI_RVALID & S_AXI_RREADY;
  assign write_complete = M_AXI_BVALID & S_AXI_BREADY;

  always @(posedge ACLK) begin : arbiter_read_ff
    if (~ARESETN)
      read_active <= 1'b0;
    else if (read_complete)
      read_active <= 1'b0;
    else if (read_req)
      read_active <= 1'b1;
  end

  always @(posedge ACLK) begin : arbiter_write_ff
    if (~ARESETN)
      write_active <= 1'b0;
    else if (write_complete)
      write_active <= 1'b0;
    else if (write_req)
      write_active <= 1'b1;
  end

  always @(posedge ACLK) begin : arbiter_busy_ff
    if (~ARESETN)
      busy <= 1'b0;
    else if (read_complete | write_complete)
      busy <= 1'b0;
    else if ((S_AXI_AWVALID & M_AXI_AWREADY & ~read_req) | (S_AXI_ARVALID & M_AXI_ARREADY & ~write_req))
      busy <= 1'b1;
  end

  assign M_AXI_ARVALID = read_req;
  assign S_AXI_ARREADY = M_AXI_ARREADY & read_req;

  assign M_AXI_AWVALID = write_req;
  assign S_AXI_AWREADY = M_AXI_AWREADY & write_req;

  assign M_AXI_RREADY  = S_AXI_RREADY & read_active;
  assign S_AXI_RVALID  = M_AXI_RVALID & read_active;

  assign M_AXI_BREADY  = S_AXI_BREADY & write_active;
  assign S_AXI_BVALID  = M_AXI_BVALID & write_active;

  // Address multiplexer
  assign m_axaddr = (read_req) ? S_AXI_ARADDR : S_AXI_AWADDR;

  // Id multiplexer and flip-flop
  reg [C_AXI_ID_WIDTH-1:0] s_axid;

  always @(posedge ACLK) begin : axid
    if      (~ARESETN)    s_axid <= {C_AXI_ID_WIDTH{1'b0}};
    else if (read_req)  s_axid <= S_AXI_ARID;
    else if (write_req) s_axid <= S_AXI_AWID;
  end

  assign S_AXI_BID = s_axid;
  assign S_AXI_RID = s_axid;

  assign M_AXI_AWADDR = m_axaddr;
  assign M_AXI_ARADDR = m_axaddr;


  // Feed-through signals
  assign S_AXI_WREADY   = M_AXI_WREADY & ~|areset_d;
  assign S_AXI_BRESP    = M_AXI_BRESP;
  assign S_AXI_RDATA    = M_AXI_RDATA;
  assign S_AXI_RRESP    = M_AXI_RRESP;
  assign S_AXI_RLAST    = 1'b1;

  assign M_AXI_WVALID   = S_AXI_WVALID & ~|areset_d;
  assign M_AXI_WDATA    = S_AXI_WDATA;
  assign M_AXI_WSTRB    = S_AXI_WSTRB;

endmodule

module Conf #(parameter ADDR_BASE = 32'd0,
parameter NREG = 4,
parameter W = 32)(
    input wire ACLK,
    input wire ARESETN,
    //AXI Inputs
    input wire [31:0] S_AXI_ARADDR,
    output wire S_AXI_ARREADY,
    input wire S_AXI_ARVALID,

    input wire [31:0] S_AXI_AWADDR,
    output wire S_AXI_AWREADY,
    input wire S_AXI_AWVALID,

    output wire [31:0] S_AXI_RDATA,
    input wire S_AXI_RREADY,
    output wire S_AXI_RVALID,

    input wire [31:0] S_AXI_WDATA,
    output wire S_AXI_WREADY,
    input wire S_AXI_WVALID,

    output wire [1:0] S_AXI_BRESP,
    output wire S_AXI_BVALID,
    input wire S_AXI_BREADY,

    input wire [11:0] S_AXI_ARID,
    input wire [11:0] S_AXI_AWID,
    output wire [11:0] S_AXI_BID,
    output wire [11:0] S_AXI_RID,
    output wire S_AXI_RLAST,
    output wire [1:0] S_AXI_RRESP,
    input wire [3:0] S_AXI_WSTRB,

    
    output wire CONFIG_VALID,
    input wire CONFIG_READY,
    output wire [NREG*W-1:0] CONFIG_DATA,
    output wire CONFIG_IRQ,

    input wire []=]..(NREG-1)..[=[:0] WRITE_DATA_VALID,
    input wire []=]..((NREG*32)-1)..[=[:0] WRITE_DATA
    );

    //Convert Input signals to AXI lite, to avoid ID matching
    wire [31:0] LITE_ARADDR;
    wire LITE_ARREADY;
    wire LITE_ARVALID;
    wire [31:0] LITE_AWADDR;
    wire LITE_AWREADY;
    wire LITE_AWVALID;
    wire LITE_BREADY;
    reg [1:0] LITE_BRESP;
    wire LITE_BVALID;
    reg [31:0] LITE_RDATA;
    wire LITE_RREADY;
    reg [1:0] LITE_RRESP;
    wire LITE_RVALID;
    wire [31:0] LITE_WDATA;
    wire LITE_WREADY;
    wire [3:0] LITE_WSTRB;
    wire LITE_WVALID;
    
    ict106_axilite_conv axilite(
    .ACLK(ACLK),
    .ARESETN(ARESETN),
    .S_AXI_ARADDR(S_AXI_ARADDR), 
    .S_AXI_ARID(S_AXI_ARID),  
    .S_AXI_ARREADY(S_AXI_ARREADY), 
    .S_AXI_ARVALID(S_AXI_ARVALID), 
    .S_AXI_AWADDR(S_AXI_AWADDR), 
    .S_AXI_AWID(S_AXI_AWID), 
    .S_AXI_AWREADY(S_AXI_AWREADY), 
    .S_AXI_AWVALID(S_AXI_AWVALID), 
    .S_AXI_BID(S_AXI_BID), 
    .S_AXI_BREADY(S_AXI_BREADY), 
    .S_AXI_BRESP(S_AXI_BRESP), 
    .S_AXI_BVALID(S_AXI_BVALID), 
    .S_AXI_RDATA(S_AXI_RDATA), 
    .S_AXI_RID(S_AXI_RID), 
    .S_AXI_RLAST(S_AXI_RLAST), 
    .S_AXI_RREADY(S_AXI_RREADY), 
    .S_AXI_RRESP(S_AXI_RRESP), 
    .S_AXI_RVALID(S_AXI_RVALID), 
    .S_AXI_WDATA(S_AXI_WDATA), 
    .S_AXI_WREADY(S_AXI_WREADY), 
    .S_AXI_WSTRB(S_AXI_WSTRB), 
    .S_AXI_WVALID(S_AXI_WVALID),
       
    .M_AXI_ARADDR(LITE_ARADDR),
    .M_AXI_ARREADY(LITE_ARREADY),
    .M_AXI_ARVALID(LITE_ARVALID),
    .M_AXI_AWADDR(LITE_AWADDR),
    .M_AXI_AWREADY(LITE_AWREADY),
    .M_AXI_AWVALID(LITE_AWVALID),
    .M_AXI_BREADY(LITE_BREADY),
    .M_AXI_BRESP(LITE_BRESP),
    .M_AXI_BVALID(LITE_BVALID),
    .M_AXI_RDATA(LITE_RDATA),
    .M_AXI_RREADY(LITE_RREADY),
    .M_AXI_RRESP(LITE_RRESP),
    .M_AXI_RVALID(LITE_RVALID),
    .M_AXI_WDATA(LITE_WDATA),
    .M_AXI_WREADY(LITE_WREADY),
    .M_AXI_WSTRB(LITE_WSTRB),
    .M_AXI_WVALID(LITE_WVALID)
  );

reg [W-1:0] data[NREG-1:0];

parameter IDLE = 0, RWAIT = 1;
parameter OK = 2'b00, SLVERR = 2'b10;

reg [31:0] counter;

//READS
reg r_state = IDLE;
wire []=]..(REG_ADDR_BITS-1)..[=[:0] r_select;
assign r_select  = LITE_ARADDR[]=]..(REG_ADDR_BITS+1)..[=[:2];

wire    ar_good;
assign ar_good = {LITE_ARADDR[31:]=]..(REG_ADDR_BITS+2)..[=[], ]=]..REG_ADDR_BITS..[=['b0, LITE_ARADDR[1:0]} == ADDR_BASE;
assign LITE_ARREADY = (r_state == IDLE);
assign LITE_RVALID = (r_state == RWAIT);
always @(posedge ACLK) begin
    if(ARESETN == 0) begin
        r_state <= IDLE;
    end else case(r_state)
        IDLE: begin
            if(LITE_ARVALID) begin
                //$display("Accepted Read Addr %x", LITE_ARADDR);
                LITE_RRESP <= ar_good ? OK : SLVERR;
                LITE_RDATA <= data[r_select];
                r_state <= RWAIT;
            end
        end
        RWAIT: begin
            if(LITE_RREADY) begin
                //$display("Master accepted read data");
                r_state <= IDLE;
            end
        end
    endcase
end 

//WRITES
reg w_state = IDLE;
reg []=]..(REG_ADDR_BITS-1)..[=[:0] w_select_r;
reg w_wrotedata = 0;
reg w_wroteresp = 0;

wire []=]..(REG_ADDR_BITS-1)..[=[:0] w_select;
assign w_select  = LITE_AWADDR[]=]..(REG_ADDR_BITS+1)..[=[:2];

wire    aw_good;
assign aw_good = {LITE_AWADDR[31:]=]..(REG_ADDR_BITS+2)..[=[], ]=]..REG_ADDR_BITS..[=['b00, LITE_AWADDR[1:0]} == ADDR_BASE;

assign LITE_AWREADY = (w_state == IDLE);
assign LITE_WREADY = (w_state == RWAIT) && !w_wrotedata;
assign LITE_BVALID = (w_state == RWAIT) && !w_wroteresp;

always @(posedge ACLK) begin
    if(ARESETN == 0) begin
        w_state <= IDLE;
        w_wrotedata <= 0;
        w_wroteresp <= 0;
    end else case(w_state)
        IDLE: begin
            if(LITE_AWVALID) begin
                ]=]..J.sel(verbose,[[$display("Accepted Write Addr %x", LITE_AWADDR);]].."\n","")..[=[
                LITE_BRESP <= aw_good ? OK : SLVERR;
                w_select_r <= w_select;
                w_state <= RWAIT; 
                w_wrotedata <= 0;
                w_wroteresp <= 0;
            end
]=]}

for i=0,NREG-1 do
table.insert(vstring,[=[
            if (WRITE_DATA_VALID[]=]..i..[=[]) begin
              data[]=]..i..[=[] <= WRITE_DATA[]=]..(i*32+31)..":"..(i*32)..[=[];
              ]=]..J.sel([[$display("IP WRITE REG ]]..i..[[ %d",WRITE_DATA[]]..(i*32+31)..":"..(i*32).."]);\n","")..[=[
            end 
]=])
end

table.insert(vstring,[=[
        end
        RWAIT: begin
]=])


for i=0,NREG-1 do
table.insert(vstring,[=[            
            if (!w_wrotedata && w_select_r==]=]..REG_ADDR_BITS..[=['d]=]..i..[=[ && LITE_WVALID) begin
                ]=]..J.sel(verbose,[[$display("AXI WRITE REG ]]..i..[[ %d",LITE_WDATA);]].."\n","")..[=[
                data[]=]..i..[=[] <= LITE_WDATA;
            end else if (WRITE_DATA_VALID[]=]..i..[=[]) begin
                ]=]..J.sel(verbose,[[$display("IP WRITE REG ]]..i..[[ %d",WRITE_DATA[]]..(i*32+31)..":"..(i*32).."]);\n","")..[=[
                data[]=]..i..[=[] <= WRITE_DATA[]=]..(i*32+31)..":"..(i*32)..[=[];
            end
]=])
end

table.insert(vstring,[=[
            if((w_wrotedata || LITE_WVALID) && (w_wroteresp || LITE_BREADY)) begin
                ]=]..J.sel(verbose,[[$display("Write done");]].."\n","")..[=[
                w_wrotedata <= 0;
                w_wroteresp <= 0;
                w_state <= IDLE;
            end else if (LITE_WVALID) begin
                ]=]..J.sel(verbose,[[$display("Accepted write data WVALID");]].."\n","")..[=[
                w_wrotedata <= 1;
            end else if (LITE_BREADY) begin
                ]=]..J.sel(verbose,[[$display("Accepted RESP");]].."\n","")..[=[
                w_wroteresp <= 1;
            end else begin
                ]=]..J.sel(verbose,[[$display("Waiting on WVALID/BREADY");]].."\n","")..[=[
            end
        end
    endcase
end

reg v_state = IDLE;
assign CONFIG_VALID = (v_state == RWAIT);
always @(posedge ACLK) begin
    if (ARESETN == 0) begin
        v_state <= IDLE;
    end else case(v_state)
        IDLE:
            if (LITE_WVALID && LITE_WREADY && w_select_r == ]=]..REG_ADDR_BITS..[=['b0) begin
                v_state <= RWAIT;
            end
        RWAIT:
            if (CONFIG_READY) begin
                v_state <= IDLE;
            end
    endcase
end
]=])

--typedef bit [NREG*W-1:0] DATATYPE;
--assign CONFIG_DATA = DATATYPE'(data);

for i=0,NREG-1 do
  table.insert(vstring,"assign CONFIG_DATA["..(i*32+31)..":"..(i*32).."] = data["..i.."];\n")
end

table.insert(vstring,[=[//how many cycles does the operation take?
always @(posedge ACLK) begin
    if (ARESETN == 0) begin
        counter <= 0;
    end else if (CONFIG_READY && CONFIG_VALID) begin
        counter <= 0;
    end else if (CONFIG_READY==1'b0) begin
        counter <= counter + 1;
    end
end

reg busy = 0;
reg busy_last = 0;
always @(posedge ACLK) begin
    if (ARESETN == 0) begin
        busy <= 0;
        busy_last <= 0;
    end else begin
        if (CONFIG_READY) begin
            busy <= CONFIG_VALID ? 1 : 0;
        end
        busy_last <= busy;
    end
end

assign CONFIG_IRQ = !busy;

endmodule

module ]=]..ModuleName..[=[(
  input wire CLK,
  input wire done_reset,
  input wire start_reset,

  input wire [32:0] IP_SAXI]=]..port..[=[_ARADDR,
  output wire IP_SAXI]=]..port..[=[_ARADDR_ready,

  input wire [32:0] IP_SAXI]=]..port..[=[_AWADDR,
  output wire IP_SAXI]=]..port..[=[_AWADDR_ready,

  output wire [32:0] IP_SAXI]=]..port..[=[_RDATA,
  input wire IP_SAXI]=]..port..[=[_RDATA_ready,

  input wire [32:0] IP_SAXI]=]..port..[=[_WDATA,
  output wire IP_SAXI]=]..port..[=[_WDATA_ready,

  output wire [2:0] IP_SAXI]=]..port..[=[_BRESP,
  input wire IP_SAXI]=]..port..[=[_BRESP_ready,

  input wire [11:0] IP_SAXI]=]..port..[=[_ARID,
  input wire [11:0] IP_SAXI]=]..port..[=[_AWID,
  output wire [11:0] IP_SAXI]=]..port..[=[_BID,
  output wire [11:0] IP_SAXI]=]..port..[=[_RID,
  output wire IP_SAXI]=]..port..[=[_RLAST,
  output wire [1:0] IP_SAXI]=]..port..[=[_RRESP,
  input wire [3:0] IP_SAXI]=]..port..[=[_WSTRB,

  // global drivers  
  ]=]..regPorts..[=[

  // done signal
  input wire done_input,
  output wire done_ready,

  // start signal
  input wire start_ready_inp,
  output wire start_output
);
parameter INSTANCE_NAME="inst";

wire CONFIG_VALID;
wire []=]..(NREG*32-1)..[=[:0] CONFIG_DATA;
wire CONFIG_IRQ;

wire []=]..(NREG-1)..[=[:0] DATA_VALID;
wire []=]..(NREG*32-1)..[=[:0] DATA;

]=]..regPortAssigns..[=[

Conf #(.ADDR_BASE(32'hA0000000),.NREG(]=]..NREG..[=[)) conf(
.ACLK(CLK),
.ARESETN(~done_reset),

.CONFIG_READY(1'b1),
.CONFIG_VALID(CONFIG_VALID),
.CONFIG_DATA(CONFIG_DATA),
.CONFIG_IRQ(CONFIG_IRQ),

.WRITE_DATA_VALID(DATA_VALID),
.WRITE_DATA(DATA),

.S_AXI_ARADDR(IP_SAXI]=]..port..[=[_ARADDR[31:0]),
.S_AXI_ARVALID(IP_SAXI]=]..port..[=[_ARADDR[32]),
.S_AXI_ARREADY(IP_SAXI]=]..port..[=[_ARADDR_ready),

.S_AXI_AWADDR(IP_SAXI]=]..port..[=[_AWADDR[31:0]),
.S_AXI_AWVALID(IP_SAXI]=]..port..[=[_AWADDR[32]),
.S_AXI_AWREADY(IP_SAXI]=]..port..[=[_AWADDR_ready),

.S_AXI_RDATA(IP_SAXI]=]..port..[=[_RDATA[31:0]),
.S_AXI_RVALID(IP_SAXI]=]..port..[=[_RDATA[32]),
.S_AXI_RREADY(IP_SAXI]=]..port..[=[_RDATA_ready),

.S_AXI_WDATA(IP_SAXI]=]..port..[=[_WDATA[31:0]),
.S_AXI_WVALID(IP_SAXI]=]..port..[=[_WDATA[32]),
.S_AXI_WREADY(IP_SAXI]=]..port..[=[_WDATA_ready),

.S_AXI_BRESP(IP_SAXI]=]..port..[=[_BRESP[1:0]),
.S_AXI_BVALID(IP_SAXI]=]..port..[=[_BRESP[2]),
.S_AXI_BREADY(IP_SAXI]=]..port..[=[_BRESP_ready),

.S_AXI_ARID(IP_SAXI]=]..port..[=[_ARID),
.S_AXI_AWID(IP_SAXI]=]..port..[=[_AWID),
.S_AXI_BID(IP_SAXI]=]..port..[=[_BID),
.S_AXI_RID(IP_SAXI]=]..port..[=[_RID),
.S_AXI_RLAST(IP_SAXI]=]..port..[=[_RLAST),
.S_AXI_RRESP(IP_SAXI]=]..port..[=[_RRESP),
.S_AXI_WSTRB(IP_SAXI]=]..port..[=[_WSTRB)
);

assign DATA_VALID[0] = 1'd0;
assign DATA_VALID[1] = done_input;
assign DATA[63:32] = 32'd1;

wire dostart;
assign dostart = CONFIG_VALID && CONFIG_DATA[31:0]==32'd1;

reg dostartReg = 1'b0;
assign start_output = dostartReg;

always @(posedge CLK) begin
  if( dostartReg && start_ready_inp ) begin
    dostartReg <= 1'b0; // reset it
  end else begin
    dostartReg <= dostartReg | dostart;
  end
end

assign done_ready = 1'b1;

endmodule

]=])

  local res = { kind="SOCREGS", name=ModuleName, inputType = R.HandshakeTrigger, outputType = R.HandshakeTrigger, delay=0, sdfInput={{1,1}}, sdfOutput={{1,1}}, registered=true, stateful=true, globals = globals, globalMetadata=globalMetadata }
  function res.makeSystolic()
    local fns = {}

    local inp = S.parameter("start_input",types.null())
    local outv = R.lower(res.outputType):fakeValue()
    fns.start = S.lambda("start",inp,S.constant(outv,R.lower(res.outputType)),"start_output")

    local inp = S.parameter("done_input",R.lower(res.inputType))
    fns.done = S.lambda("done",inp,nil,"done_output")

    local rinp =  S.parameter("done_ready_inp",types.null())
    fns.done_ready = S.lambda( "done_ready", rinp, S.constant(R.extractReady(res.inputType):fakeValue(),R.extractReady(res.inputType)), "done_ready")

    local rinp =  S.parameter("start_ready_inp", R.extractReady(res.outputType))
    fns.start_ready = S.lambda( "start_ready", rinp, nil, "start_ready")

    fns.start_reset = S.lambda("start_reset",S.parameter("rnil_start",types.null()),nil,"start_reset_out",{},S.parameter("start_reset",types.bool()))
    fns.done_reset = S.lambda("done_reset",S.parameter("rnil_done",types.null()),nil,"done_reset_out",{},S.parameter("done_reset",types.bool()))

    local SC = {}
    for g,_ in pairs(globals) do
      SC[g.systolicValue] = 1
      if g.systolicValueReady~=nil then SC[g.systolicValueReady] = 1 end
    end
    
    return S.module.new( ModuleName,fns,{},true,nil,table.concat(vstring),{start=0,done=0,ready=0},SC)
  end

  res =  R.newFunction(res)

  -- hack
  if terralib~=nil then
    res.makeTerra=nil
    res.terraModule = SOCMT.axiRegs(res,tab,port)
  end

  for k,v in pairs(addToModuleHack) do
    assert(res[k]==nil)
    res[k] = R.readGlobal("readGlobal_"..k,v)
  end
                        
  return res
end)

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
  
  local res = RM.liftVerilog( ModuleName, R.HandshakeTrigger, R.Handshake(types.bits(64)),
[=[module ]=]..ModuleName..[=[_inner(
    //AXI port
    input wire ACLK,
    input wire ARESETN,
    output reg [31:0] M_AXI_ARADDR,
    input wire M_AXI_ARREADY,
    output wire  M_AXI_ARVALID,
    input wire [63:0] M_AXI_RDATA,
    output wire M_AXI_RREADY,
    input wire [1:0] M_AXI_RRESP,
    input wire M_AXI_RVALID,
    input wire M_AXI_RLAST,
    output wire [3:0] M_AXI_ARLEN,
    output wire [1:0] M_AXI_ARSIZE,
    output wire [1:0] M_AXI_ARBURST,
    
    //Control config
    input wire CONFIG_VALID,
    output wire CONFIG_READY,
    input wire [31:0] CONFIG_START_ADDR,
    input wire [31:0] CONFIG_NBYTES,
    
    //RAM port
    input wire DATA_READY_DOWNSTREAM,
    output wire DATA_VALID,
    output wire [63:0] DATA
);

assign M_AXI_ARLEN = 4'b1111;
assign M_AXI_ARSIZE = 2'b11;
assign M_AXI_ARBURST = 2'b01;
parameter IDLE = 0, RWAIT = 1;
    
//ADDR logic
reg [24:0] a_count = 0;
reg a_state = IDLE;
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
                if(a_count - 1 == 0) begin
                    a_state <= IDLE;
                end
                a_count <= a_count - 1;
                M_AXI_ARADDR <= M_AXI_ARADDR + 128; // Bursts are 128 bytes long
            end
        end
    endcase
end
    
//READ logic
reg [31:0] b_count = 0;
reg r_state = IDLE;
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
                if (b_count - 8 == 0) begin
                    r_state <= IDLE;
                end
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
    input wire CLK,
    input wire reset,

    output wire [32:0] IP_MAXI]=]..port..[=[_ARADDR,
    input wire IP_MAXI]=]..port..[=[_ARADDR_ready,

    input wire [64:0] IP_MAXI]=]..port..[=[_RDATA,
    output wire IP_MAXI]=]..port..[=[_RDATA_ready,

    input wire [1:0] IP_MAXI]=]..port..[=[_RRESP,

    input wire IP_MAXI]=]..port..[=[_RLAST,
    output wire [3:0] IP_MAXI]=]..port..[=[_ARLEN,
    output wire [1:0] IP_MAXI]=]..port..[=[_ARSIZE,
    output wire [1:0] IP_MAXI]=]..port..[=[_ARBURST,
    
    //Control config
    input wire process_input,
    output wire ready,
    
//    input wire [31:0] CONFIG_START_ADDR,
//    input wire [31:0] CONFIG_NBYTES,
    
    //RAM port
    input wire ready_downstream,
    output wire [64:0] process_output
    
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
]=],globals,globalMetadata,{{1,(Nbytes/8)}},{{1,1}})

  if terralib~=nil then
    res.makeTerra = nil
    res.terraModule = SOCMT.axiBurstReadN( res, Nbytes, port, address )
  end

  return res
end)

SOC.axiReadBytes = J.memoize(function(filename,Nbytes,port,addressBase, X)
  J.err( type(port)=="number", "axiReadBytes: port must be number" )
  J.err( port>=0 and port<=SOC.ports,"axiReadBytes: port out of range" )
  J.err( type(Nbytes)=="number","axiReadBytes: Nbytes must be number" )
  J.err( Nbytes%8==0, "axiReadBytes: Nbytes must have 8 as a factor" )
  J.err( Nbytes>=8, "axiReadBytes: NYI - Nbytes must be >=8" )
  J.err( X==nil, "axiReadBytes: too many arguments" )
  J.err( type(addressBase)=="number", "axiReadBytes: addressBase must be number")
  
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

  local ModuleName = J.sanitize("AXI_READ_BYTES_"..tostring(Nbytes).."_"..tostring(port))

  local burstCount = Nbytes/8
  J.err( burstCount<=16,"axiReadBytes: NYI - burst longer than 16")
  
  local res = RM.liftVerilog( ModuleName, R.Handshake(types.uint(32)), R.Handshake(types.bits(64)),
[=[module ]=]..ModuleName..[=[(
    input wire CLK,
    input wire reset,

    output wire [32:0] IP_MAXI]=]..port..[=[_ARADDR,
    input wire IP_MAXI]=]..port..[=[_ARADDR_ready,

    input wire [64:0] IP_MAXI]=]..port..[=[_RDATA,
    output wire IP_MAXI]=]..port..[=[_RDATA_ready,

    input wire [1:0] IP_MAXI]=]..port..[=[_RRESP,
    input wire IP_MAXI]=]..port..[=[_RLAST,
    output wire [3:0] IP_MAXI]=]..port..[=[_ARLEN,
    output wire [1:0] IP_MAXI]=]..port..[=[_ARSIZE,
    output wire [1:0] IP_MAXI]=]..port..[=[_ARBURST,
    
    input wire [32:0] process_input,
    output wire ready,

    output wire [64:0] process_output,
    input wire ready_downstream
);
parameter INSTANCE_NAME="inst";

assign IP_MAXI]=]..port..[=[_ARLEN = 4'd]=]..(burstCount-1)..[=[; // length of burst
assign IP_MAXI]=]..port..[=[_ARSIZE = 2'b11; // number of bytes per transfer
assign IP_MAXI]=]..port..[=[_ARBURST = 2'b01; // burst mode

assign IP_MAXI]=]..port..[=[_ARADDR = process_input + 32'd]=]..addressBase..[=[;
assign ready = IP_MAXI]=]..port..[=[_ARADDR_ready;

assign process_output = IP_MAXI]=]..port..[=[_RDATA;
assign IP_MAXI]=]..port..[=[_RDATA_ready = ready_downstream;

//always @(posedge CLK) begin
//  $display("piv %d pi %d",process_input[32],process_input[31:0]);
//end

endmodule
]=],globals,globalMetadata,{{1,burstCount}},{{1,1}})

  if terralib~=nil then
    res.makeTerra = nil
    res.terraModule = SOCMT.axiReadBytes( res, Nbytes, port, addressBase )
  end

  return res
end)

SOC.axiBurstWriteN = J.memoize(function(filename,Nbytes,port,address,X)
  J.err( type(filename)=="string","axiBurstWriteN: filename must be string")
  J.err( type(port)=="number", "axiBurstWriteN: port must be number" )
  J.err( port>=0 and port<=SOC.ports,"axiBurstWriteN: port out of range" )
  J.err( type(Nbytes)=="number","axiBurstWriteN: Nbytes must be number")
  J.err( type(address)=="number","axiBurstWriteN: missing address")
  J.err( X==nil, "axiBurstWriteN: too many arguments" )

  assert(Nbytes%128==0)

  local Nburst = Nbytes/128
  
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

  local res = RM.liftVerilog( "DRAMWriter", R.Handshake(types.bits(64)), R.HandshakeTrigger, 
[=[module DRAMWriterInner(
    //AXI port
    input wire ACLK,
    input wire ARESETN,
    output reg [31:0] M_AXI_AWADDR,
    input wire M_AXI_AWREADY,
    output wire M_AXI_AWVALID,
    
    output wire [63:0] M_AXI_WDATA,
    output wire [7:0] M_AXI_WSTRB,
    input wire M_AXI_WREADY,
    output wire M_AXI_WVALID,
    output wire M_AXI_WLAST,
    
    input wire [1:0] M_AXI_BRESP,
    input wire M_AXI_BVALID,
    output wire M_AXI_BREADY,
    
    output wire [3:0] M_AXI_AWLEN,
    output wire [1:0] M_AXI_AWSIZE,
    output wire [1:0] M_AXI_AWBURST,
    
    //Control config
    input wire CONFIG_VALID,
    output wire CONFIG_READY,
    input wire [31:0] CONFIG_START_ADDR,
    input wire [31:0] CONFIG_NBYTES,
    
    //RAM port
    input wire [63:0] DATA,
    output wire DATA_READY,
    input wire DATA_VALID,

    input wire doneReady,
    output wire done
);

assign M_AXI_AWLEN = 4'b1111;
assign M_AXI_AWSIZE = 2'b11;
assign M_AXI_AWBURST = 2'b01;
assign M_AXI_WSTRB = 8'b11111111;

parameter IDLE = 0, RWAIT = 1;

reg [31:0] BRESP_CNT = 32'd0;
    
//ADDR logic
reg [24:0] a_count = 0;
reg a_state = IDLE;
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
                if(a_count - 1 == 0) begin
                    a_state <= IDLE;
                end
                a_count <= a_count - 1;
                M_AXI_AWADDR <= M_AXI_AWADDR + 128; 
            end
        end
    endcase
end

//WRITE logic
reg [31:0] b_count = 0;
reg w_state = IDLE;
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

always @(posedge ACLK) begin
  if (ARESETN == 0) begin
    BRESP_CNT <= 32'd0;
  end else if (BRESP_CNT==32'd]=]..Nburst..[=[ && doneReady) begin
    BRESP_CNT <= 32'd0;
  end else if (M_AXI_BVALID) begin
    BRESP_CNT <= BRESP_CNT + 32'd1;
  end
end

assign done = BRESP_CNT==32'd]=]..Nburst..[=[;

reg [3:0] last_count;
assign M_AXI_WLAST = last_count == 4'b0000;

assign M_AXI_WVALID = (w_state == RWAIT) && DATA_VALID && (a_count<CONFIG_NBYTES[31:7]);

assign DATA_READY = (w_state == RWAIT) && M_AXI_WREADY && (a_count<CONFIG_NBYTES[31:7]);
   
assign CONFIG_READY = (w_state == IDLE) && (a_state == IDLE);

assign M_AXI_BREADY = 1;

assign M_AXI_WDATA = DATA;

endmodule // DRAMWriter

module DRAMWriter(
    //AXI port
    input wire CLK,
    input wire reset,
    output reg [32:0] IP_MAXI]=]..port..[=[_AWADDR,
    input wire IP_MAXI]=]..port..[=[_AWADDR_ready,
    
    output wire [64:0] IP_MAXI]=]..port..[=[_WDATA,
    input wire IP_MAXI]=]..port..[=[_WDATA_ready,

    output wire [7:0] IP_MAXI]=]..port..[=[_WSTRB,
    output wire IP_MAXI]=]..port..[=[_WLAST,
    
    input wire [2:0] IP_MAXI]=]..port..[=[_BRESP,
    output wire IP_MAXI]=]..port..[=[_BRESP_ready,
    
    output wire [3:0] IP_MAXI]=]..port..[=[_AWLEN,
    output wire [1:0] IP_MAXI]=]..port..[=[_AWSIZE,
    output wire [1:0] IP_MAXI]=]..port..[=[_AWBURST,
    
    //Control config
//    input wire CONFIG_VALID,
//    output wire CONFIG_READY,
//    input wire [31:0] CONFIG_START_ADDR,
//    input wire [31:0] CONFIG_NBYTES,
    
    //RAM port
    input wire [64:0] process_input,
    output wire ready,

    output wire process_output,
    input wire ready_downstream
);
parameter INSTANCE_NAME="inst";

//assign process_output=1'b0;

wire CONFIG_READY;
wire DATA_READY;

//reg HACK = 1'b1;

// HACK: to drive CONFIG_VALID, wait until we are not in reset, and DRAMWriterInner has accepted CONFIG_VALID
// (this will happen once it sets ready=true). Then set CONFIG_VALID to false to keep it from writing multiple times
//always @(posedge CLK) begin
//  if(reset==1'b0 && ready) begin
//    HACK <= 1'b0;
//  end
//end

reg [63:0] firstBuffer;
reg firstBufferSet = 1'b0;

assign ready = (DATA_READY|CONFIG_READY) && firstBufferSet==1'b0;

always@(posedge CLK) begin
  if (reset) begin
    firstBufferSet <= 1'b0;
  end else if (process_input[64] && CONFIG_READY && firstBufferSet==1'b0 ) begin
    firstBufferSet <= 1'b1;
    firstBuffer <= process_input[63:0];
  end else if (DATA_READY) begin
    firstBufferSet <= 1'b0;
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
    .CONFIG_VALID(firstBufferSet),
    .CONFIG_READY(CONFIG_READY),
    .CONFIG_START_ADDR(32'h]=]..string.format('%x',address)..[=[),
    .CONFIG_NBYTES(32'd]=]..Nbytes..[=[),
    
    //RAM port
    .DATA( firstBufferSet? firstBuffer : process_input[63:0] ),
    .DATA_READY(DATA_READY),
    .DATA_VALID(process_input[64] || (firstBufferSet && CONFIG_READY==1'b0) ),

    .done(process_output),
    .doneReady(ready_downstream)
);

//always @(posedge CLK) begin
//  $display("DRAMWRITER ready: %d valid %d firstBufferSet:%d DATA_READY:%d CONFIG_READY:%d",ready,process_input[64],firstBufferSet,DATA_READY,CONFIG_READY);
//end

endmodule

]=],globals, globalMetadata,{{1,1}},{{1,Nbytes/8}})

  if terralib~=nil then
    res.makeTerra = nil
    res.terraModule = SOCMT.axiBurstWriteN( res, Nbytes, port, address )
  end

  return res
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
  J.err( nbytes%8==0,"NYI - readBurst requires 8-byte aligned size" )
  --J.err( nbytes%128==0,"NYI - readBurst requires 128-byte aligned size" )
  J.err( V==nil or type(V)=="number", "readBurst: V must be number or nil")
  if V==nil then V=0 end
  J.err(X==nil, "readBurst: too many arguments")
  
  local globalMetadata={}
  globalMetadata["MAXI"..SOC.currentMAXIReadPort.."_read_W"] = W
  globalMetadata["MAXI"..SOC.currentMAXIReadPort.."_read_H"] = H
  globalMetadata["MAXI"..SOC.currentMAXIReadPort.."_read_V"] = V
  globalMetadata["MAXI"..SOC.currentMAXIReadPort.."_read_type"] = tostring(ty)
  globalMetadata["MAXI"..SOC.currentMAXIReadPort.."_read_bitsPerPixel"] = ty:verilogBits()
  globalMetadata["MAXI"..SOC.currentMAXIReadPort.."_read_address"] = SOC.currentAddr
  
  local inp = R.input(R.HandshakeTrigger)

  local readBytes = J.upToNearest(128,nbytes)
  local out = SOC.axiBurstReadN(filename,readBytes,SOC.currentMAXIReadPort,SOC.currentAddr)(inp)

  if readBytes~=nbytes then
    out = RM.makeHandshake(C.arrayop(types.bits(64),1))(out)
    out = RM.liftHandshake(RM.liftDecimate(RM.cropSeq(types.bits(64),readBytes/8,1,1,0,(readBytes-nbytes)/8,0,0)))(out)
    out = RM.makeHandshake(C.index(types.array2d(types.bits(64),1),0))(out)
  end
  
  local outBits = ty:verilogBits()*math.max(V,1)

  local outType = ty
  if outBits<64 then
    local N = 64/ty:verilogBits()
    J.err(math.floor(N)==N,"ReadBurst: type bits must divide 64")
    out = RM.makeHandshake(C.cast(types.bits(64),types.array2d(ty,N)))(out)
    out = RM.liftHandshake(RM.changeRate(ty,1,N,math.max(V,1)))(out)

    if V==0 then
      out = RM.makeHandshake(C.index(types.array2d(ty,1),0))(out)
    end
  elseif outBits>64 then
    local N = ty:verilogBits()/64
    J.err(math.floor(N)==N,"ReadBurst: 64 must divide type bits")
    --out = RM.liftHandshake(RM.changeRate(ty,1,N,V))(out)
    assert(false) --NYI
  else
    if V>0 then outType=types.array2d(outType,V) end
    out = RM.makeHandshake(C.cast(types.bits(64),outType))(out)
  end

  local res = RM.lambda("ReadBurst_Wf"..W.."_H"..H.."_v"..V.."_port"..SOC.currentMAXIReadPort.."_addr"..SOC.currentAddr.."_"..tostring(ty),inp,out,nil,nil,nil,globalMetadata)

  SOC.currentMAXIReadPort = SOC.currentMAXIReadPort+1
  SOC.currentAddr = SOC.currentAddr+readBytes

  return res
end)

-- This works like C pointer deallocation:
-- input address N of type T actually reads at physical memory address N*sizeof(T)+base
SOC.read = J.memoize(function(filename,fileBytes,readType,X)
  J.err( type(filename)=="string","read: filename must be string")
  J.err( types.isType(readType), "read: type must be type")
  J.err( readType:verilogBits()%8==0, "SOC.read: NYI - type must be byte aligned")
  J.err( readType:verilogBits()%64==0, "SOC.read: NYI - type must be 8 byte aligned")
  
  local globalMetadata={}
  globalMetadata["MAXI"..SOC.currentMAXIReadPort.."_read_address"] = SOC.currentAddr

  local inp = R.input(R.Handshake(types.uint(32)))
  local out = inp

  local readBytesPerBurst

  -- scale by type size
  out = RM.makeHandshake(C.multiplyConst(types.uint(32),readType:verilogBits()/8))(out)
  
  if readType:verilogBits()/8 > 8*16 then
    -- longer than 1 burst, need to do multiple bursts
    J.err( (readType:verilogBits()/8) % 8*16 == 0, "SOC.read: NYI - read sizes that aren't 128-byte burst aligned")
    readBytesPerBurst = 128
    local nBursts = (readType:verilogBits()/8) / (8*16)

    out = RM.triggeredCounter(types.uint(32),nBursts,128)(out)
  else
    readBytesPerBurst = readType:verilogBits()/8
  end
  
  out = SOC.axiReadBytes( filename, readBytesPerBurst, SOC.currentMAXIReadPort, SOC.currentAddr )(out)

  local N = readType:verilogBits()/64
  
  if readType:verilogBits()==64 then
    out = RM.makeHandshake(C.bitcast(types.bits(64),readType))(out)
  elseif readType:verilogBits()>64 then
    out = RM.makeHandshake(C.arrayop(types.bits(64),1,1))(out)

    out = RM.liftHandshake(RM.changeRate(types.bits(64),1,1,N))(out)

    out = RM.makeHandshake(C.bitcast(types.array2d(types.bits(64),N),readType))(out)
  else
    assert(false)
  end

  local res = RM.lambda("Read_port"..SOC.currentMAXIReadPort.."_addr"..SOC.currentAddr.."_"..tostring(readType),inp,out,nil,nil,nil,globalMetadata)
  
  SOC.currentMAXIReadPort = SOC.currentMAXIReadPort+1
  SOC.currentAddr = SOC.currentAddr+fileBytes
  
  return res
end)
                          
SOC.writeBurst = J.memoize(function(filename,W,H,ty,V,X)
  J.err( type(filename)=="string","writeBurst: filename must be string")
  J.err( type(W)=="number", "writeBurst: W must be number")
  J.err( type(H)=="number", "writeBurst: H must be number")
  J.err( types.isType(ty), "writeBurst: type must be type")
  J.err(ty:verilogBits()%8==0,"NYI - writeBurst currently required byte-aligned data")
  local nbytes = W*H*(ty:verilogBits()/8)
  J.err( nbytes%8==0,"NYI - writeBurst requires 8-byte aligned size (input bytes is: "..nbytes..")" )
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

  local itype = ty
  if V>0 then itype = types.array2d(itype,V) end
  
  local inp = R.input(R.Handshake(itype))
  local out = inp
  
  if itype:verilogBits()<64 then
    local N = 64/ty:verilogBits()
    J.err(math.floor(N)==N,"SOC.writeBurst: type bits must divide 64")

    if V==0 then
      out = RM.makeHandshake(C.arrayop(ty,1))(out)
    end

    out = RM.liftHandshake(RM.changeRate(ty,1,math.max(V,1),N))(out)
    out = RM.makeHandshake(C.cast(types.array2d(ty,N),types.bits(64)))(out)
  elseif itype:verilogBits()>64 then
    assert(false) -- NYI
  else
    out = RM.makeHandshake(C.cast(itype,types.bits(64)))(out)
  end

  local writeBytes = J.upToNearest(128,nbytes)
  if writeBytes~=nbytes then
    out = RM.makeHandshake(C.arrayop(types.bits(64),1))(out)
    out = RM.liftHandshake(RM.padSeq(types.bits(64),nbytes/8,1,1,0,(writeBytes-nbytes)/8,0,0,0))(out)
    out = RM.makeHandshake(C.index(types.array2d(types.bits(64),1),0))(out)
  end
  
  out = SOC.axiBurstWriteN(filename,writeBytes,SOC.currentMAXIWritePort,SOC.currentAddr)(out)
  
  local res = RM.lambda("WriteBurst_W"..W.."_H"..H.."_v"..V.."_port"..SOC.currentMAXIWritePort.."_addr"..SOC.currentAddr.."_"..tostring(ty),inp,out,nil,nil,nil,globalMetadata)

  SOC.currentMAXIWritePort = SOC.currentMAXIWritePort+1
  SOC.currentAddr = SOC.currentAddr+nbytes

  return res
end)


function SOC.export(t)
  if t==nil then t=_G end
  for k,v in pairs(SOC) do rawset(t,k,v) end
end


return SOC
