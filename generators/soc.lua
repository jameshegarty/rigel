local R = require "rigel"
local RM = require "generators.modules"
local S = require "systolic"
local types = require "types"
local J = require "common"
local types = require "types"
local C = require "generators.examplescommon"
local SDF = require "sdf"
local Uniform = require "uniform"
local AXI = require "generators.axi"

local SOCMT

if terralib~=nil then
  SOCMT = require("generators.socTerra")
end

local SOC = {}

SOC.ports = 4
SOC.currentMAXIReadPort = 0
SOC.currentMAXIWritePort = 0
SOC.currentSAXIPort = 0
SOC.currentAddr = 0x30008000
SOC.currentRegAddr = 0xA0000008 -- first 8 bytes are start/done bit

-- a stub for module that provides registers
SOC.regStub = J.memoize(function(tab)
  local fns = {}
  for k,v in pairs(tab) do
    J.err( type(k)=="string", "axiRegs: key must be string" )
    J.err( types.isType(v[1]), "axiRegs: first key must be type" )
    J.err( R.isBasic(v[1]), "axiRegs: type must be basic type")
    --J.err( v[1]:toCPUType()==v[1], "axiRegs: NYI - input type must be a CPU type" )
    v[1]:checkLuaValue(v[2])
    fns[k] = R.newFunction{name=k, inputType=types.Interface(), outputType=types.S(types.Par(v[1])), sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=false, delay=0}
  end

  local name = J.sanitize("RegStub_"..tostring(tab))

  local function makeSystolic()
    local fns = {}
    local delays = {}
    for k,v in pairs(tab) do
      local inp = S.parameter(k.."_input",types.null())
      fns[k] = S.lambda(k,inp,S.constant(v[2],v[1]),k.."_output")
      delays[k]=0
    end
    return S.module.new( name,fns,{},true,nil,"",delays)
  end

  local res = R.newModule{ name=name, functions=fns, stateful=false, makeSystolic=makeSystolic }

  res.makeTerra=function() return SOCMT.regStub( res, tab ) end
  
  return res
end)

SOC.axiRegs = J.memoize(function( tab, rate, X )
  J.err( type(tab)=="table","SOC.axiRegs: input must be table")
  J.err( J.keycount(tab)==#tab, "SOC.axiRegs: input must be an array")
  
  J.err( X==nil, "soc.axiRegs: too many arguments")

  local port = SOC.currentSAXIPort
  SOC.currentSAXIPort = SOC.currentSAXIPort + 1

  if rate==nil then rate = SDF{1,1} end
  J.err( SDF.isSDF(rate), "SOC.axiRegs: rate should be SDF rate" )
  
  local globalMetadata = {}
  local functionList = {}

  functionList.read = R.newFunction{name="Read",inputType=AXI.ReadAddress32,outputType=AXI.ReadData32,sdfInput=SDF{1,1},sdfOutput=SDF{1,1}, stateful=false, delay=0}
  functionList.write = R.newFunction{name="Write",inputType=AXI.WriteIssue32, outputType=AXI.WriteResponse32, sdfInput=SDF{{1,1},{1,1}},sdfOutput=SDF{1,1}, stateful=false, delay=0}

  local NREG = 2
  local curDataBit = 64 -- for start/done
  local instanceList = {}
  local regRange = {}
  for _,v in ipairs(tab) do
    local regname, regmod = v[1],v[2]
    J.err( type(regname)=="string", "axiRegs: first value must be string" )
    J.err( R.isPlainModule(regmod), "axiRegs: second value must be a delegate module" )
    J.err( regmod.type:toCPUType()==regmod.type, "axiRegs: NYI - input type must be a CPU type" )

    local inst = regmod:instantiate(regname)
    table.insert(instanceList,inst)

    local range = {NREG}
    NREG = NREG + math.max(regmod.type:verilogBits()/32,1)
    range[2]=NREG
    table.insert(regRange,range)
    
    assert(regmod.type:verilogBits()%4==0) -- for hex
    globalMetadata["Register_"..string.format("%x",SOC.currentRegAddr)] = regmod.type:valueToHex(regmod.init)
    globalMetadata["AddrOfRegister_".."InstCall_regs_"..regname] = SOC.currentRegAddr --string.format("%x",SOC.currentRegAddr)
    globalMetadata["TypeOfRegister_".."InstCall_regs_"..regname] = regmod.type

    if regmod.functions.write1~=nil then
      functionList[regname] = R.newFunction{name=regname, inputType=R.Handshake(regmod.type), outputType=types.Interface(), sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=false, delay=0}
    else
      functionList[regname] = R.newFunction{name=regname, inputType=types.Interface(), outputType=types.S(types.Par(regmod.type)), sdfInput=SDF{1,1}, sdfOutput=SDF{1,1}, stateful=false, delay=0}
    end
    
    SOC.currentRegAddr = SOC.currentRegAddr + math.ceil(regmod.type:verilogBits()/32)*4
    curDataBit = curDataBit + math.max(regmod.type:verilogBits(),32)
  end
  
  local ModuleName = J.sanitize("Regs_"..tostring(tab).."_"..tostring(port))

  local REG_ADDR_BITS = math.ceil(math.log(NREG)/math.log(2))
  
  local verbose = false

  functionList.start = R.newFunction{name="start",inputType=types.Interface(), outputType=R.HandshakeTrigger, sdfInput=rate,sdfOutput=rate, sdfExact=true, stateful=true, delay=0}
  functionList.done = R.newFunction{name="done", inputType=R.HandshakeTrigger, outputType=types.Interface(), sdfInput=rate,sdfOutput=rate, sdfExact=true, stateful=true, delay=0}

  local res = RM.moduleLambda( ModuleName, functionList, instanceList )
  res.globalMetadata = globalMetadata

  res.makeSystolic = function()
    local s = C.automaticSystolicStub(res)

        local vstring={[=[
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

]=]}
  local W = 32
  local ADDR_BASE = "32'hA0000000"


  table.insert(vstring, res:vHeader()..res:vInstances())

  -- wire instance fns to external fns
  for _,v in pairs(tab) do
    if v[2].functions.write1~=nil then
      table.insert(vstring, "assign "..v[1].."_write1_input = "..v[1].."_input["..(v[2].type:verilogBits()-1)..":0];\n")
      table.insert(vstring, "assign "..v[1].."_write1_valid = "..v[1].."_input["..v[2].type:verilogBits().."];\n")
      table.insert(vstring, "assign "..v[1].."_write1_CE = 1'b1;\n")
      table.insert(vstring, "assign "..v[1].."_ready = 1'b1;\n")
    else
      table.insert(vstring, "assign "..v[1].."_output = "..v[1].."_read1_output;\n")
    end
  end
  
  table.insert(vstring,[=[

    wire CONFIG_VALID; // output

    wire CONFIG_READY;
    assign CONFIG_READY = 1'b1;

    wire [31:0] S_AXI_ARADDR; //input
    assign S_AXI_ARADDR = read_input]=]..AXI.ReadAddressVSelect.araddr..[=[;
    wire S_AXI_ARREADY; //output
    assign read_ready = S_AXI_ARREADY;
    wire S_AXI_ARVALID; //input
    assign S_AXI_ARVALID = read_input]=]..AXI.ReadAddressVSelect.arvalid..[=[;

    wire [31:0] S_AXI_AWADDR; //input
    assign S_AXI_AWADDR = write_input]=]..AXI.WriteIssueVSelect(32).awaddr..[=[;
    wire S_AXI_AWREADY; //output
    assign write_ready[0] = S_AXI_AWREADY;
    wire S_AXI_AWVALID; //input
    assign S_AXI_AWVALID = write_input]=]..AXI.WriteIssueVSelect(32).awvalid..[=[;

    wire [31:0] S_AXI_RDATA; //output
    assign read_output]=]..AXI.ReadDataVSelect(32).rdata..[=[ = S_AXI_RDATA;
    wire S_AXI_RREADY; //input
    assign S_AXI_RREADY = read_ready_downstream;
    wire S_AXI_RVALID; //output
    assign read_output]=]..AXI.ReadDataVSelect(32).rvalid..[=[ = S_AXI_RVALID;

    wire [31:0] S_AXI_WDATA; //input
    assign S_AXI_WDATA = write_input]=]..AXI.WriteIssueVSelect(32).wdata..[=[;
    wire S_AXI_WREADY; //output
    assign write_ready[1] = S_AXI_WREADY;
    wire S_AXI_WVALID; //input
    assign S_AXI_WVALID = write_input]=]..AXI.WriteIssueVSelect(32).wvalid..[=[;

    wire [1:0] S_AXI_BRESP; //output
    assign write_output]=]..AXI.WriteResponseVSelect(32).bresp..[=[ = S_AXI_BRESP;
    wire S_AXI_BVALID; //output
    assign write_output]=]..AXI.WriteResponseVSelect(32).bvalid..[=[ = S_AXI_BVALID;
    wire S_AXI_BREADY; //input
    assign S_AXI_BREADY = write_ready_downstream;

    wire [11:0] S_AXI_ARID; //input
    assign S_AXI_ARID = read_input]=]..AXI.ReadAddressVSelect.arid..[=[;
    wire [11:0] S_AXI_AWID; //input
    assign S_AXI_AWID = write_input]=]..AXI.WriteIssueVSelect(32).awid..[=[;
    wire [11:0] S_AXI_BID; //output
    assign write_output]=]..AXI.WriteResponseVSelect(32).bid..[=[ = S_AXI_BID;
    wire [11:0] S_AXI_RID; //out
    assign read_output]=]..AXI.ReadDataVSelect(32).rid..[=[ = S_AXI_RID;
    wire S_AXI_RLAST; //out
    assign read_output]=]..AXI.ReadDataVSelect(32).rlast..[=[ = S_AXI_RLAST;
    wire [1:0] S_AXI_RRESP; //out 
    assign read_output]=]..AXI.ReadDataVSelect(32).rresp..[=[ = S_AXI_RRESP;
    wire [3:0] S_AXI_WSTRB; //input
    assign S_AXI_WSTRB = write_input]=]..AXI.WriteIssueVSelect(32).wstrb..[=[;

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
    .ACLK(CLK),
    .ARESETN(~reset),
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

reg []=]..W..[=[-1:0] data[]=]..NREG..[=[-1:0];
reg [31:0] startreg;  // always at addr 0, bits 31:0
reg [31:0] donereg;   // always at addr 1, bits 63:32

parameter IDLE = 0, RWAIT = 1;
parameter OK = 2'b00, SLVERR = 2'b10;

//reg [31:0] counter;

//READS
reg r_state = IDLE;
wire []=]..(REG_ADDR_BITS-1)..[=[:0] r_select;
assign r_select  = LITE_ARADDR[]=]..(REG_ADDR_BITS+1)..[=[:2];
]=])

-- async read logic
for k,v in ipairs(tab) do
  local range = regRange[k]
  table.insert(vstring,"assign "..v[1].."_read_input = {"..(32-REG_ADDR_BITS).."'d0,r_select}-32'd"..range[1]..";\n")
end

table.insert(vstring,[=[
wire    ar_good;
assign ar_good = {LITE_ARADDR[31:]=]..(REG_ADDR_BITS+2)..[=[], ]=]..REG_ADDR_BITS..[=['b0, LITE_ARADDR[1:0]} == ]=]..ADDR_BASE..[=[;
assign LITE_ARREADY = (r_state == IDLE);
assign LITE_RVALID = (r_state == RWAIT);
always @(posedge CLK) begin
    if(reset == 1'b1) begin
        r_state <= IDLE;
    end else case(r_state)
        IDLE: begin
            if(LITE_ARVALID) begin
                //$display("Accepted Read Addr %x", LITE_ARADDR);
                LITE_RRESP <= ar_good ? OK : SLVERR;
                //LITE_RDATA <= data[r_select];

                if (r_select==]=]..(REG_ADDR_BITS)..[=['d0) begin
                  LITE_RDATA <= startreg;
                end

                if (r_select==]=]..(REG_ADDR_BITS)..[=['d1) begin
                  LITE_RDATA <= donereg;
                end]=])

        -- read logic
for k,v in ipairs(tab) do
  local range = regRange[k]

  table.insert(vstring,[=[
                if (r_select>=]=]..(REG_ADDR_BITS).."'d"..range[1]..J.sel(k<#tab,[=[ && r_select<]=]..(REG_ADDR_BITS).."'d"..range[2],"")..[=[) begin
                  LITE_RDATA <= ]=]..v[1]..[=[_read_output;
                end]=])

end
       
table.insert(vstring,[=[                r_state <= RWAIT;
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

]=])

-- async write logic
for k,v in ipairs(tab) do
  local range = regRange[k]

  table.insert(vstring,"assign "..v[1].."_write_valid = !w_wrotedata && w_select_r>="..REG_ADDR_BITS.."'d"..range[1]..J.sel(k<#tab,[=[ && w_select_r<]=]..REG_ADDR_BITS.."'d"..range[2],"")..[=[ && LITE_WVALID;
assign ]=]..v[1].."_write_CE = "..v[1]..[=[_write_valid;
assign ]=]..v[1]..[=[_write_input =  {LITE_WDATA,]=]..(32-REG_ADDR_BITS)..[=['d0,w_select_r-]=]..REG_ADDR_BITS.."'d"..range[1]..[=[};
]=])

end

table.insert(vstring,[=[wire    aw_good;
assign aw_good = {LITE_AWADDR[31:]=]..(REG_ADDR_BITS+2)..[=[], ]=]..REG_ADDR_BITS..[=['b00, LITE_AWADDR[1:0]} == ]=]..ADDR_BASE..[=[;

assign LITE_AWREADY = (w_state == IDLE);
assign LITE_WREADY = (w_state == RWAIT) && !w_wrotedata;
assign LITE_BVALID = (w_state == RWAIT) && !w_wroteresp;

always @(posedge CLK) begin
    if(reset == 1'b1) begin
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
        end
        RWAIT: begin
]=])

-- hard code the writes to start/done
table.insert(vstring,[=[            
            if (!w_wrotedata && w_select_r==]=]..REG_ADDR_BITS..[=['d0 && LITE_WVALID) begin
                ]=]..J.sel(verbose,[[$display("AXI WRITE REG 0 %d",LITE_WDATA);]].."\n","")..[=[
                startreg <= LITE_WDATA;
            end
]=])

-- don't do this: only IP can write to done reg, to prevent multiple drivers
--table.insert(vstring,[=[            
--            if (!w_wrotedata && w_select_r==]=]..REG_ADDR_BITS..[=['d1 && LITE_WVALID) begin
--                ]=]..J.sel(verbose,[[$display("AXI WRITE REG 1 %d",LITE_WDATA);]].."\n","")..[=[
--                donereg <= LITE_WDATA;
--            end
--]=])

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
always @(posedge CLK) begin
    if (reset == 1'b1) begin
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

// deal with the start/done bit
wire dostart;
assign dostart = CONFIG_VALID && startreg==32'd1;

reg dostartReg = 1'b0;
assign start_output = dostartReg;

always @(posedge CLK) begin
  if(reset) begin
    dostartReg <= 1'b0;
    startreg <= 32'b0;
    donereg <= 32'b0;
  end else begin
    if( dostartReg && start_ready_downstream ) begin
      dostartReg <= 1'b0; // once IP sees the start trigger, reset it
    end else begin
      dostartReg <= dostartReg | dostart;
    end

    if (done_input) begin
      donereg <= 32'd1;
    end
  end
end

assign done_ready = 1'b1;

endmodule

]=])

    s:verilog(table.concat(vstring))
    return s
  end
  
  -- hack
  if terralib~=nil then
    res.makeTerra=nil
    res.terraModule = SOCMT.axiRegs( res, tab )
  end

  return res
end)

function SOC.axiBurstReadN( filename, Nbytes, address, readFn, X )
  return SOC.axiBurstReadNInner( filename, Uniform(Nbytes), Uniform(address), readFn, X )
end

-- does a 128 byte burst
-- uint25 addr -> bits(64)
SOC.axiBurstReadNInner = J.memoize(function(filename,Nbytes,address,readFn_orig,X)
  assert(Uniform.isUniform(Nbytes))
  J.err( (Nbytes%128):eq(0):assertAlwaysTrue(), "AxiBurstReadN: Nbytes must have 128 as a factor, but is: "..tostring(Nbytes) )
  assert(Uniform.isUniform(address))
  J.err( R.isFunction(readFn_orig), "axiBurstReadN: readFn should be rigel function, but is: "..tostring(readFn_orig))
  J.err( X==nil, "axiBurstReadN: too many arguments" )

  local readFn = readFn_orig
  J.err( R.isFunction(readFn), "axiReadBytes: readFn should be rigel function, but is: "..tostring(readFn))

  if readFn.inputType==AXI.ReadAddress and readFn.outputType==AXI.ReadData64 then
    readFn = C.ConvertVRtoRV(readFn)
  end
  
  J.err( readFn.inputType == types.Handshake(AXI.ReadAddressTuple), "axiReadBytes expected HandshakeRV input type, but was: "..tostring(readFn.inputType) )
  J.err( readFn.outputType == types.Handshake(AXI.ReadDataTuple(64)), "axiReadBytes expected HandshakeRV output type, but was: "..tostring(readFn.outputType) )

  local globalMetadata = {}
  globalMetadata[readFn_orig.name.."_read_filename"] = filename
  globalMetadata[readFn_orig.name.."_read_address"] = address

  local ModuleName = J.sanitize("DRAMReader_"..tostring(Nbytes).."_"..tostring(address))

  local readFnInst = readFn:instantiate("ReadFn")
  --local RPORT = readFn.instance.name.."_"..readFn.functionName
  --local RIN = readFn.instance.name.."_"..readFn.functionName.."_input"
  --local ROUT = readFn.instance.name.."_"..readFn.functionName
  
  local function vstr(res)
    return [=[module ]=]..ModuleName..[=[_inner(
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
    output wire []=]..(AXI.ReadAddressTuple.list[AXI.ReadAddressIdx.arlen+1]:verilogBits()-1)..[=[:0] M_AXI_ARLEN,
    output wire []=]..(AXI.ReadAddressTuple.list[AXI.ReadAddressIdx.arsize+1]:verilogBits()-1)..[=[:0] M_AXI_ARSIZE,
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

assign M_AXI_ARLEN = ]=]..(AXI.ReadAddressTuple.list[AXI.ReadAddressIdx.arlen+1]:verilogBits())..[=['b1111;
assign M_AXI_ARSIZE = ]=]..(AXI.ReadAddressTuple.list[AXI.ReadAddressIdx.arsize+1]:verilogBits())..[=['b11;
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

module ]=]..ModuleName..[=[_ported(
    //AXI port
    input wire CLK,
    input wire reset,

    output wire [32:0] IP_MAXI_ARADDR,
    input wire IP_MAXI_ARADDR_ready,

    input wire [64:0] IP_MAXI_RDATA,
    output wire IP_MAXI_RDATA_ready,

    input wire [1:0] IP_MAXI_RRESP,

    input wire IP_MAXI_RLAST,
    output wire []=]..(AXI.ReadAddressTuple.list[AXI.ReadAddressIdx.arlen+1]:verilogBits()-1)..[=[:0] IP_MAXI_ARLEN,
    output wire []=]..(AXI.ReadAddressTuple.list[AXI.ReadAddressIdx.arsize+1]:verilogBits()-1)..[=[:0] IP_MAXI_ARSIZE,
    output wire [1:0] IP_MAXI_ARBURST,
    
    //Control config
    input wire process_input,
    output wire ready,
    
    input wire [31:0] CONFIG_START_ADDR,
    input wire [31:0] CONFIG_NBYTES,

    //RAM port
    input wire ready_downstream,
    output wire [64:0] process_output
    
);
parameter INSTANCE_NAME="inst";


]=]..ModuleName..[=[_inner inner(
    //AXI port
    .ACLK(CLK),
    .ARESETN(~reset),

    .M_AXI_ARADDR(IP_MAXI_ARADDR[31:0]),
    .M_AXI_ARREADY(IP_MAXI_ARADDR_ready),
    .M_AXI_ARVALID(IP_MAXI_ARADDR[32]),

    .M_AXI_RDATA(IP_MAXI_RDATA[63:0]),
    .M_AXI_RREADY(IP_MAXI_RDATA_ready),
    .M_AXI_RVALID(IP_MAXI_RDATA[64]),

    .M_AXI_RRESP(IP_MAXI_RRESP),

    .M_AXI_RLAST(IP_MAXI_RLAST),
    .M_AXI_ARLEN(IP_MAXI_ARLEN),
    .M_AXI_ARSIZE(IP_MAXI_ARSIZE),
    .M_AXI_ARBURST(IP_MAXI_ARBURST),
    
    //Control config
    .CONFIG_VALID(process_input),
    .CONFIG_READY(ready),
    .CONFIG_START_ADDR(CONFIG_START_ADDR),
    .CONFIG_NBYTES(CONFIG_NBYTES),
    
    //RAM port
    .DATA_READY_DOWNSTREAM(ready_downstream),
    .DATA_VALID(process_output[64]),
    .DATA(process_output[63:0])
);

endmodule

]=]..res:vHeader()..readFnInst:toVerilog()..address:toVerilogInstance()..Nbytes:toVerilogInstance()..[=[

  ]=]..ModuleName..[=[_ported inner(
    .CLK(CLK),
    .reset(reset),
    .process_input(process_input),
    .ready(ready),
    .ready_downstream(ready_downstream),
    .process_output(process_output),
    .CONFIG_START_ADDR(]=]..address:toVerilog(types.uint(32))..[=[),
    .CONFIG_NBYTES(]=]..Nbytes:toVerilog(types.uint(32))..[=[),

    .IP_MAXI_ARADDR({]=]..readFnInst:vInput()..AXI.ReadAddressVSelect.arvalid..","..readFnInst:vInput()..AXI.ReadAddressVSelect.araddr..[=[}),
    .IP_MAXI_ARADDR_ready(]=]..readFnInst:vInputReady()..[=[),
    .IP_MAXI_ARLEN(]=]..readFnInst:vInput()..AXI.ReadAddressVSelect.arlen..[=[),
    .IP_MAXI_ARSIZE(]=]..readFnInst:vInput()..AXI.ReadAddressVSelect.arsize..[=[),
    .IP_MAXI_ARBURST(]=]..readFnInst:vInput()..AXI.ReadAddressVSelect.arburst..[=[),

    .IP_MAXI_RDATA({]=]..readFnInst:vOutput()..AXI.ReadDataVSelect(64).rvalid..","..readFnInst:vOutput()..AXI.ReadDataVSelect(64).rdata..[=[}),
    .IP_MAXI_RDATA_ready(]=]..readFnInst:vOutputReady()..[=[),
    .IP_MAXI_RLAST(]=]..readFnInst:vOutput()..AXI.ReadDataVSelect(64).rlast..[=[),
    .IP_MAXI_RRESP(]=]..readFnInst:vOutput()..AXI.ReadDataVSelect(64).rresp..[=[)
);

endmodule
]=]
  end
  
  local instanceMap = {[readFnInst]=1}
  instanceMap = J.joinSet(instanceMap,address:getInstances())
  instanceMap = J.joinSet(instanceMap,Nbytes:getInstances())
  
  local res = RM.liftVerilogTab{ name=ModuleName, inputType=R.HandshakeTrigger, outputType=R.Handshake(types.bits(64)), vstr=vstr, globalMetadata=globalMetadata, sdfInput={{1,(Nbytes/8)}}, sdfOutput={{1,1}}, instanceMap=instanceMap, delay=10, inputBurstiness=2 }

  -- hack: have it throttle outputs
  res.outputBurstiness = 2
  
  if terralib~=nil then
    res.makeTerra = function() return  SOCMT.axiBurstReadN( res, Nbytes, address, readFn ) end
  end
  
  return res
end)

SOC.axiReadBytes = J.memoize(function( filename, Nbytes, port, addressBase_orig, readFn_orig, X )
  J.err( type(port)=="number", "axiReadBytes: port must be number" )
  J.err( port>=0 and port<=SOC.ports,"axiReadBytes: port out of range" )
  J.err( type(Nbytes)=="number","axiReadBytes: Nbytes must be number" )

  local readFn = readFn_orig
  J.err( R.isFunction(readFn), "axiReadBytes: readFn should be rigel function, but is: "..tostring(readFn))

  if readFn.inputType==AXI.ReadAddress and readFn.outputType==AXI.ReadData64 then
    readFn = C.ConvertVRtoRV(readFn)
  end
  
  J.err( readFn.inputType == types.Handshake(AXI.ReadAddressTuple), "axiReadBytes expected HandshakeRV input type, but was: "..tostring(readFn.inputType) )
  J.err( readFn.outputType == types.Handshake(AXI.ReadDataTuple(64)), "axiReadBytes expected HandshakeRV output type, but was: "..tostring(readFn.outputType) )
  J.err( X==nil, "axiReadBytes: too many arguments" )

  local addressBase = Uniform(addressBase_orig)
  
  local globalMetadata = {}
  globalMetadata[readFn_orig.name.."_read_filename"] = filename

  local ModuleName = J.sanitize("AXI_READ_BYTES_"..tostring(Nbytes).."_"..tostring(port))

  local burstCount = math.ceil(Nbytes/8)
  J.err( burstCount<=16,"axiReadBytes: NYI - burst longer than 16")

  local readFnInst = readFn:instantiate("ReadFn")
  
  local function vstr(res)
    return res:vHeader()..res:vInstances()..[=[
assign ]=]..readFnInst:vInput()..AXI.ReadAddressVSelect.arlen.." = "..(AXI.ReadAddressTuple.list[AXI.ReadAddressIdx.arlen+1]:verilogBits()).."'d"..(burstCount-1)..[=[; // length of burst
assign ]=]..readFnInst:vInput()..AXI.ReadAddressVSelect.arsize..[=[ = ]=]..(AXI.ReadAddressTuple.list[AXI.ReadAddressIdx.arsize+1]:verilogBits())..[=['b11; // number of bytes per transfer
assign ]=]..readFnInst:vInput()..AXI.ReadAddressVSelect.arburst..[=[ = 2'b01; // burst mode

assign ]=]..readFnInst:vInput()..AXI.ReadAddressVSelect.arvalid..[=[ = process_input[32];
assign ]=]..readFnInst:vInput()..AXI.ReadAddressVSelect.araddr..[=[ = process_input[31:0] + ]=]..addressBase:toVerilog(types.uint(32))..[=[;
assign ready = ]=]..readFnInst:vInputReady()..[=[;

assign process_output[63:0] = ]=]..readFnInst:vOutput()..AXI.ReadDataVSelect(64).rdata..[=[;
assign process_output[64] = ]=]..readFnInst:vOutput()..AXI.ReadDataVSelect(64).rvalid..[=[;
assign ]=]..readFnInst:vOutputReady()..[=[ = ready_downstream;

//always @(posedge CLK) begin
//  $display("piv %d pi %d",process_input[32],process_input[31:0]);
//end

endmodule
]=]
  end
  
  local instanceMap = {[readFnInst]=1}
  instanceMap = J.joinSet(instanceMap,addressBase:getInstances())
  
  local res = RM.liftVerilogTab{ name=ModuleName, inputType=R.Handshake(types.uint(32)), outputType=R.Handshake(types.bits(64)), vstr=vstr, globalMetadata=globalMetadata, sdfInput={{1,burstCount}}, sdfOutput={{1,1}}, instanceMap=instanceMap, delay=4 }

  if terralib~=nil then
    res.makeTerra = nil
    res.terraModule = SOCMT.axiReadBytes( res, Nbytes, port, addressBase, readFn_orig )
  end

  --return SOC.AXIWrapRV(res,port)
  return res
end)

SOC.axiWriteBytes = J.memoize(function( filename, NbytesPerCycle, port, addressBase_orig, writeFn_orig, X)
  J.err( type(port)=="number", "axiWriteBytes: port must be number" )
  J.err( port>=0 and port<=SOC.ports,"axiWriteBytes: port out of range" )
  J.err( type(NbytesPerCycle)=="number","axiWriteBytes: NbytesPerCycle must be number" )
  J.err( NbytesPerCycle==math.floor(NbytesPerCycle), "axiWriteBytes: NbytesPerCycle must be integer" )
  if NbytesPerCycle>8 then
    J.err( NbytesPerCycle%8==0, "axiWriteBytes: NYI - NbytePerCycle must be 64 bit aligned")
  end
  J.err( R.isFunction(writeFn_orig), "axiWriteBytes: writeFn should be rigel function, but is: "..tostring(writeFn_orig))
  J.err( X==nil, "axiWriteBytes: too many arguments" )
  local addressBase = Uniform(addressBase_orig)
  
  local globalMetadata = {}
  globalMetadata[writeFn_orig.name.."_write_filename"] = filename
  
  local ModuleName = J.sanitize("AXI_WRITE_BYTES_"..tostring(NbytesPerCycle).."_"..tostring(port))

  local burstCount = NbytesPerCycle/8
  J.err( burstCount<=16,"axiWriteBytes: NYI - burst longer than 16")

  local strb = "11111111"
  if NbytesPerCycle<8 then
    strb=""
    for i=1,NbytesPerCycle do strb=strb.."1" end
  end

  local Nbits = math.min(64,NbytesPerCycle*8)

  local last
  local bursts = NbytesPerCycle/8

  local writeFnInst = writeFn_orig:instantiate("writeFn")
  
  if NbytesPerCycle<=8 then
    --    last = "assign IP_MAXI"..port.."_WLAST = 1'b1;\n"
    last = "assign "..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).wlast.." = 1'b1;\n"
  else
    last = [=[
reg [3:0] last_count = 4'd]=]..bursts..[=[;
always @(posedge CLK) begin
  if reset==1'b1 begin
    last_count <= 4'd]=]..bursts..[=[;
  end else begin
    if (IP_MAXI]=]..port..[=[_AWADDR_RV_ready && IP_MAXI]=]..port..[=[_AWADDR_RV[32] ) begin
      last_count <= last_count - 4'b1;
    end
  end
assign IP_MAXI]=]..port..[=[_WLAST = (last_count==4'd0);
end
]=]
  end

  local inputType = R.HandshakeTuple{types.uint(32),types.bits(Nbits)}

  local function vstr(res)
    return res:vHeader()..writeFnInst:toVerilog()..addressBase:toVerilogInstance()..[=[
assign ]=]..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).awlen..[=[ = ]=]..(AXI.WriteAddress.list[AXI.WriteAddressIdx.awlen+1]:verilogBits())..[=['d]=]..(burstCount-1)..[=[; // length of burst
assign ]=]..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).awsize..[=[ = ]=]..(AXI.WriteAddress.list[AXI.WriteAddressIdx.awsize+1]:verilogBits())..[=['b11; // number of bytes per transfer
assign ]=]..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).awburst..[=[ = 2'b01; // burst mode
assign ]=]..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).wstrb..[=[ = 8'b]=]..strb..[=[; // burst mode

assign ]=]..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).awaddr..[=[ = process_input[31:0] + (]=]..addressBase:toVerilog(types.uint(32))..[=[);
assign ]=]..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).awvalid..[=[ = process_input[32];
assign ready = ]=]..writeFnInst:vInputReady()..[=[;

//always @(posedge CLK) begin
//  $display("AWADDR_READY=%d WDATA_READY=%d AWVALID=%d",ZynqNOC_write_ready[0],ZynqNOC_write_ready[1],process_input[32]);
//end

assign ]=]..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).wdata..[=[ = process_input[]=]..(Nbits+32)..[=[:33];
assign ]=]..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).wvalid..[=[ = process_input[]=]..(Nbits+32+1)..[=[];

]=]..last..[=[
assign process_output = ]=]..writeFnInst:vOutput()..AXI.WriteResponseVSelect(64).bvalid..[=[;
assign ]=]..writeFnInst:vOutputReady()..[=[ = ready_downstream;

endmodule
]=]
  end
  
  local instanceMap = {[writeFnInst]=1}
  instanceMap = J.joinSet(instanceMap,addressBase:getInstances())
  
  -- input format is {addr,data}
  local res = RM.liftVerilogTab{ name=ModuleName, inputType=inputType, outputType=R.HandshakeTrigger, vstr=vstr, globalMetadata=globalMetadata, sdfInput={{1,1},{1,1}}, sdfOutput={{1,1}}, instanceMap=instanceMap, delay=4}

  if terralib~=nil then
    res.makeTerra = nil
    res.terraModule = SOCMT.axiWriteBytes( res, NbytesPerCycle, port, addressBase, writeFn_orig )
  end

  return res
end)

function SOC.axiBurstWriteN( filename, Nbytes, address, writeFn, X )
  return SOC.axiBurstWriteNInner( filename, Uniform(Nbytes), Uniform(address), writeFn, X )
end

SOC.axiBurstWriteNInner = J.memoize(function( filename, Nbytes, address, writeFn_orig, X )
  J.err( type(filename)=="string","axiBurstWriteN: filename must be string")

  assert( Uniform.isUniform(Nbytes) )
  assert( Uniform.isUniform(address) )
  
  J.err( R.isFunction(writeFn_orig), "axiBurstWriteN: writeFn should be rigel function, but is: ",writeFn_orig)
  J.err( X==nil, "axiBurstWriteN: too many arguments" )

  J.err( Uniform(Nbytes%128):eq(0):assertAlwaysTrue(), "SOC.axiBurstWriteN: Nbytes ("..tostring(Nbytes)..") not 128-byte aligned")

  local writeFn = writeFn_orig

  J.err( writeFn.inputType == AXI.WriteIssue64, "axiBurstWriteN expected AXI.WriteIssue64 input type, but was: "..tostring(writeFn.inputType) )
  J.err( writeFn.outputType == AXI.WriteResponse64, "axiReadBytes expected AXI.WriteResponse64 output type, but was: "..tostring(writeFn.outputType) )

  local writeFnInst = writeFn:instantiate("writeFn")
  
  local Nburst = Nbytes/128
  
  local globalMetadata = {}
  globalMetadata[writeFn_orig.name.."_write_filename"] = filename
  globalMetadata[writeFn_orig.name.."_write_address"] = address
  globalMetadata[writeFn_orig.name.."_write_W"] = Nbytes
  globalMetadata[writeFn_orig.name.."_write_H"] = 1
  globalMetadata[writeFn_orig.name.."_write_bitsPerPixel"] = 8

  local moduleNameSuffix=J.sanitize("_file"..tostring(filename).."_Nbytes"..tostring(Nbytes).."_address"..tostring(address))
  
  local function vstr(res)

    return [=[module DRAMWriterInner]=]..moduleNameSuffix..[=[(
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
    
    output wire []=]..(AXI.WriteAddress.list[AXI.WriteAddressIdx.awlen+1]:verilogBits()-1)..[=[:0] M_AXI_AWLEN,
    output wire []=]..(AXI.WriteAddress.list[AXI.WriteAddressIdx.awsize+1]:verilogBits()-1)..[=[:0] M_AXI_AWSIZE,
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

assign M_AXI_AWLEN = ]=]..(AXI.WriteAddress.list[AXI.WriteAddressIdx.awlen+1]:verilogBits())..[=['b1111;
assign M_AXI_AWSIZE = ]=]..(AXI.WriteAddress.list[AXI.WriteAddressIdx.awsize+1]:verilogBits())..[=['b11;
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
            if(CONFIG_VALID && CONFIG_READY) begin
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
reg [3:0] last_count;

always @(posedge ACLK) begin
    if (ARESETN == 0) begin
        w_state <= IDLE;
        b_count <= 0;
    end else case(w_state)
        IDLE: begin
            if(CONFIG_VALID && CONFIG_READY) begin
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
  end else if (BRESP_CNT==(]=]..Nburst:toVerilog(types.uint(32))..[=[) && doneReady) begin
    BRESP_CNT <= 32'd0;
  end else if (M_AXI_BVALID) begin
    BRESP_CNT <= BRESP_CNT + 32'd1;
  end
end

assign done = BRESP_CNT==(]=]..Nburst:toVerilog(types.uint(32))..[=[);

assign M_AXI_WLAST = last_count == 4'b0000;

assign M_AXI_WVALID = (w_state == RWAIT) && DATA_VALID && (a_count<CONFIG_NBYTES[31:7]);

assign DATA_READY = (w_state == RWAIT) && M_AXI_WREADY && (a_count<CONFIG_NBYTES[31:7]);
   
assign CONFIG_READY = (w_state == IDLE) && (a_state == IDLE);

assign M_AXI_BREADY = 1;

assign M_AXI_WDATA = DATA;

endmodule // DRAMWriter

module DRAMWriter_ported]=]..moduleNameSuffix..[=[(
    //AXI port
    input wire CLK,
    input wire reset,
    output reg [32:0] IP_MAXI_AWADDR,
    input wire IP_MAXI_AWADDR_ready,
    
    output wire [64:0] IP_MAXI_WDATA,
    input wire IP_MAXI_WDATA_ready,

    output wire [7:0] IP_MAXI_WSTRB,
    output wire IP_MAXI_WLAST,
    
    input wire [2:0] IP_MAXI_BRESP,
    output wire IP_MAXI_BRESP_ready,
    
    output wire []=]..(AXI.WriteAddress.list[AXI.WriteAddressIdx.awlen+1]:verilogBits()-1)..[=[:0] IP_MAXI_AWLEN,
    output wire []=]..(AXI.WriteAddress.list[AXI.WriteAddressIdx.awsize+1]:verilogBits()-1)..[=[:0] IP_MAXI_AWSIZE,
    output wire [1:0] IP_MAXI_AWBURST,
    
    //Control config
//    input wire CONFIG_VALID,
//    output wire CONFIG_READY,
    input wire [31:0] CONFIG_START_ADDR,
    input wire [31:0] CONFIG_NBYTES,

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
$display("FIRST BUFFER SET");
  end else if (DATA_READY) begin
    firstBufferSet <= 1'b0;
  end
end

DRAMWriterInner]=]..moduleNameSuffix..[=[ inner(
    //AXI port
    .ACLK(CLK),
    .ARESETN(~reset),

    .M_AXI_AWADDR(IP_MAXI_AWADDR[31:0]),
    .M_AXI_AWREADY(IP_MAXI_AWADDR_ready),
    .M_AXI_AWVALID(IP_MAXI_AWADDR[32]),
    
    .M_AXI_WDATA(IP_MAXI_WDATA[63:0]),
    .M_AXI_WREADY(IP_MAXI_WDATA_ready),
    .M_AXI_WVALID(IP_MAXI_WDATA[64]),

    .M_AXI_BRESP(IP_MAXI_BRESP[1:0]),
    .M_AXI_BVALID(IP_MAXI_BRESP[2]),
    .M_AXI_BREADY(IP_MAXI_BRESP_ready),

    .M_AXI_WSTRB(IP_MAXI_WSTRB),
    .M_AXI_WLAST(IP_MAXI_WLAST),
    .M_AXI_AWLEN(IP_MAXI_AWLEN),
    .M_AXI_AWSIZE(IP_MAXI_AWSIZE),
    .M_AXI_AWBURST(IP_MAXI_AWBURST),
    
    //Control config
    .CONFIG_VALID(firstBufferSet),
    .CONFIG_READY(CONFIG_READY),
    .CONFIG_START_ADDR(CONFIG_START_ADDR),
    .CONFIG_NBYTES(CONFIG_NBYTES),
    
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

]=]..res:vHeader()..writeFnInst:toVerilog()..address:toVerilogInstance()..Nbytes:toVerilogInstance()..[=[

  DRAMWriter_ported]=]..moduleNameSuffix..[=[ ported(.CLK(CLK),
    .reset(reset),
    .process_input(process_input),
    .ready(ready),
    .process_output(process_output),
    .ready_downstream(ready_downstream),

    .CONFIG_START_ADDR(]=]..address:toVerilog(types.uint(32))..[=[),
    .CONFIG_NBYTES(]=]..Nbytes:toVerilog(types.uint(32))..[=[),

    .IP_MAXI_AWADDR({]=]..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).awvalid..[=[,]=]..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).awaddr..[=[}),
    .IP_MAXI_AWLEN(]=]..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).awlen..[=[),
    .IP_MAXI_AWBURST(]=]..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).awburst..[=[),
    .IP_MAXI_AWSIZE(]=]..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).awsize..[=[),
    .IP_MAXI_AWADDR_ready(]=]..writeFnInst:vInputReady()..[=[[0]),

    .IP_MAXI_WDATA({]=]..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).wvalid..[=[,]=]..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).wdata..[=[}),
    .IP_MAXI_WSTRB(]=]..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).wstrb..[=[),
    .IP_MAXI_WLAST(]=]..writeFnInst:vInput()..AXI.WriteIssueVSelect(64).wlast..[=[),
    .IP_MAXI_WDATA_ready(]=]..writeFnInst:vInputReady()..[=[[1]),

    .IP_MAXI_BRESP({]=]..writeFnInst:vOutput()..AXI.WriteResponseVSelect(64).bvalid..[=[,]=]..writeFnInst:vOutput()..AXI.WriteResponseVSelect(64).bresp..[=[}),

    .IP_MAXI_BRESP_ready(]=]..writeFnInst:vOutputReady()..[=[)
);
endmodule

]=]
  end
  
  local instanceMap = {[writeFnInst]=1}
  instanceMap = J.joinSet(instanceMap,address:getInstances())
  instanceMap = J.joinSet(instanceMap,Nbytes:getInstances())

  local res = RM.liftVerilogTab{ name="DRAMWriter"..moduleNameSuffix, inputType=R.Handshake(types.bits(64)), outputType=R.HandshakeTrigger, vstr=vstr, globalMetadata=globalMetadata, sdfInput={{1,1}}, sdfOutput={{1,Nbytes/8}}, instanceMap=instanceMap, delay=(Nbytes:toNumber()/8)+8, inputBurstiness=8, outputBurstiness=1 }

  if terralib~=nil then
    res.makeTerra = nil
    res.terraModule = SOCMT.axiBurstWriteN( res, Nbytes, address, writeFn )
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

-- this generator wraps a readFn (which always does a 128 byte burst), and makes it able to service any W/H/V that's requested
SOC.readBurst = J.memoize(function( filename, W_orig, H_orig, ty, V, framed, addressOverride, readFn_orig, X )
  J.err( type(filename)=="string","readBurst: filename must be string")

  local W = Uniform(W_orig)
  local H = Uniform(H_orig)
  J.err( types.isType(ty), "readBurst: type must be type, but is: ",ty)
  J.err( types.isBasic(ty), "readBurst: type must be basic type, but is: ",ty)
  J.err( ty:verilogBits()%8==0,"NYI - readBurst currently required byte-aligned data, but type is: ",ty)

  J.err( V==nil or type(V)=="number", "readBurst: V must be number or nil")
  if V==nil then V=0 end

  J.err( framed==nil or type(framed)=="boolean", "framed must be nil or bool, but is: ",framed)
  J.err(X==nil, "readBurst: too many arguments")

  J.err( R.isFunction(readFn_orig), "SOC.readBurst: readFn should be rigel function, but is: ",readFn_orig)

  local address
  if addressOverride~=nil then
    address = Uniform(addressOverride)
  else
    assert(type(SOC.currentAddr)=="number")
    address = Uniform(SOC.currentAddr)
  end
  
  local globalMetadata={}
  globalMetadata[readFn_orig.name.."_read_W"] = W
  globalMetadata[readFn_orig.name.."_read_H"] = H
  globalMetadata[readFn_orig.name.."_read_V"] = V
  globalMetadata[readFn_orig.name.."_read_type"] = tostring(ty)
  globalMetadata[readFn_orig.name.."_read_bitsPerPixel"] = ty:verilogBits()
  globalMetadata[readFn_orig.name.."_read_address"] = address
  
  local inp = R.input(R.HandshakeTrigger)

  local outputBits = ty:verilogBits()*math.max(V,1)
  local desiredTotalOutputBits = W*H*ty:verilogBits()

  local CR = C.generalizedChangeRate( 64,0,128*8, outputBits, desiredTotalOutputBits,1 )
  local ChangeRateModule, totalBits = CR[1], CR[2]

  assert( (Uniform(totalBits)%(128*8)):eq(0):assertAlwaysTrue() )
  J.err( (Uniform(totalBits)%Uniform(outputBits)):eq(0):assertAlwaysTrue(),"readBurst: error, totalBits does not divide outputBits? totalBits=",totalBits," outputBits=",outputBits )
  assert( Uniform(totalBits):ge(desiredTotalOutputBits):assertAlwaysTrue() )

  local BRN = SOC.axiBurstReadN( filename, totalBits/8, address, readFn_orig )
  local out = BRN(inp)

  out = ChangeRateModule(out)

  if totalBits~=desiredTotalOutputBits then
    out = RM.makeHandshake(C.arrayop(types.bits(outputBits),1))(out)
    out = RM.liftHandshake(RM.liftDecimate(RM.cropSeq(types.bits(outputBits),totalBits/outputBits,1,1,0,(totalBits-desiredTotalOutputBits)/outputBits,0,0)))(out)
    out = RM.makeHandshake(C.index(types.array2d(types.bits(outputBits),1),0))(out)
  end

  local outType = ty
  if V>0 then outType=types.array2d(outType,V) end
  out = RM.makeHandshake(C.cast(types.bits(outType:verilogBits()),outType))(out)

  
  local res = RM.lambda("ReadBurst_W"..tostring(W_orig).."_H"..tostring(H_orig).."_v"..V.."_port"..SOC.currentMAXIReadPort.."_addr"..tostring(address).."_framed"..tostring(framed).."_"..tostring(ty),inp,out,nil,nil,nil,globalMetadata)

  if framed then
    if V==0 then
      res.outputType = types.RV(types.Seq(types.Par(ty),W_orig,H_orig))
    else
      res.outputType = types.RV(types.ParSeq(outType,W_orig,H_orig))
    end
  end
    
  SOC.currentMAXIReadPort = SOC.currentMAXIReadPort+1

  if addressOverride==nil then
    SOC.currentAddr = SOC.currentAddr+totalBits:maximum()/8
    assert(type(SOC.currentAddr)=="number")
  else
    assert(type(SOC.currentAddr)=="number")
    SOC.currentAddr = math.max(SOC.currentAddr,address:maximum()+(totalBits:maximum()/8))
  end
  
  return res
end)

-- if Cstyle==true, This works like C pointer deallocation:
-- input address N of type T actually reads at physical memory address N*sizeof(T)+base
-- readType: this is the output type we want
-- NOTE: do not memoize! this thing allocates a port
SOC.read = function( filename, fileBytes, readType, readFn_orig, Cstyle, addressBase_orig, X )
  J.err( type(filename)=="string","SOC.read: filename must be string, but is: "..tostring(filename))
  J.err( types.isType(readType), "SOC.read: type must be type, but is: "..tostring(readType))
  J.err( types.isBasic(readType), "SOC.read: type must be basic type, but is: "..tostring(readType))
  J.err( readType:verilogBits()%8==0, "SOC.read: NYI - type must be byte aligned, but is: "..tostring(readType))
  if Cstyle==nil then Cstyle=true end
  J.err( type(Cstyle)=="boolean","SOC.read: Cstyle should be bool")
  J.err( X==nil, "SOC.read: too many arguments" )

  J.err( R.isFunction(readFn_orig), "SOC.readBurst: readFn should be rigel function, but is: "..tostring(readFn_orig))

  local globalMetadata={}

  local address
  if addressBase_orig~=nil then
    address = Uniform(addressBase_orig)
  else
    assert(type(SOC.currentAddr)=="number")
    address = SOC.currentAddr
  end

  globalMetadata[readFn_orig.name.."_read_address"] = address
  
  local inp = R.input(R.Handshake(types.uint(32)))
  local out = inp

  local readBytesPerBurst

  -- scale by type size
  if Cstyle then
    out = RM.makeHandshake(C.multiplyConst(types.uint(32),readType:verilogBits()/8))(out)
  end
  
  if readType:verilogBits()/8 > 8*16 then
    -- longer than 1 burst, need to do multiple bursts
    J.err( (readType:verilogBits()/8) % 8*16 == 0, "SOC.read: NYI - read sizes that aren't 128-byte burst aligned")
    readBytesPerBurst = 128
    local nBursts = (readType:verilogBits()/8) / (8*16)

    out = RM.triggeredCounter(types.uint(32),nBursts,128)(out)
  else
    readBytesPerBurst = readType:verilogBits()/8
  end
  
  out = SOC.axiReadBytes( filename, readBytesPerBurst, SOC.currentMAXIReadPort, address, readFn_orig )(out)

  local N = readType:verilogBits()/64
  
  if readType:verilogBits()==64 then
    out = RM.makeHandshake(C.bitcast(types.bits(64),readType))(out)
  elseif readType:verilogBits()>64 then
    out = RM.makeHandshake(C.arrayop(types.bits(64),1,1))(out)

    out = RM.liftHandshake(RM.changeRate(types.bits(64),1,1,N))(out)

    out = RM.makeHandshake(C.bitcast(types.array2d(types.bits(64),N),readType))(out)
  elseif readType:verilogBits()<64 then
    out = RM.makeHandshake(C.bitSlice(types.bits(64),0,readType:verilogBits()-1))(out)
    out = RM.makeHandshake(C.bitcast(types.bits(readType:verilogBits()),readType))(out)
  else
    assert(false)
  end

  local res = RM.lambda( "Read_port"..SOC.currentMAXIReadPort.."_addr"..tostring(address).."_"..tostring(readType), inp, out, nil, nil, nil, globalMetadata )
  
  SOC.currentMAXIReadPort = SOC.currentMAXIReadPort+1

  if addressBase_orig==nil then
    SOC.currentAddr = SOC.currentAddr+fileBytes
    assert(type(SOC.currentAddr)=="number")
  end
  
  return res
end
                          
SOC.writeBurst = J.memoize(function( filename, W_orig, H_orig, ty, Vw, Vh, framed, writeFn_orig, addressOverride, X)
  J.err( type(filename)=="string","writeBurst: filename must be string, but is: "..tostring(filename))
  --J.err( type(W)=="number", "writeBurst: W must be number, but is: "..tostring(W))
  --J.err( type(H)=="number", "writeBurst: H must be number")
  local W,H = Uniform(W_orig):toNumber(),Uniform(H_orig):toNumber()
  J.err( types.isType(ty), "writeBurst: type must be type")

  J.err( Vw==nil or type(Vw)=="number", "writeBurst: Vw must be number or nil")
  if Vw==nil then Vw=1 end
  J.err( Vh==nil or type(Vh)=="number", "writeBurst: Vh must be number or nil, but is: "..tostring(Vh))
  if Vh==nil then Vh=1 end

  if framed==nil then framed=false end
  J.err( type(framed)=="boolean","writeBurst: framed must be boolean, but is: "..tostring(framed))
  J.err( R.isFunction(writeFn_orig), "writeBurst: writeFn should be rigel function, but is: ",writeFn_orig)
  J.err(X==nil, "writeBurst: too many arguments")

  assert(type(SOC.currentAddr)=="number")
  local address = Uniform(SOC.currentAddr)
  if addressOverride~=nil then
    address = Uniform(addressOverride)
  end
  
  local globalMetadata={}
  globalMetadata[writeFn_orig.name.."_write_W"] = W
  globalMetadata[writeFn_orig.name.."_write_H"] = H
  globalMetadata[writeFn_orig.name.."_write_V"] = Vw*Vh
  globalMetadata[writeFn_orig.name.."_write_type"] = tostring(ty)
  globalMetadata[writeFn_orig.name.."_write_bitsPerPixel"] = ty:verilogBits()
  globalMetadata[writeFn_orig.name.."_write_address"] = address

  local inputType = ty
  if Vw>0 then inputType = types.array2d(inputType,Vw,Vh) end
  
  local inp = R.input(R.Handshake(inputType))
  local out = RM.makeHandshake(C.bitcast(inputType,types.bits(inputType:verilogBits())))(inp)

  local inputBits = ty:verilogBits()*math.max(Vw*Vh,1)
  local desiredTotalInputBits = W*H*ty:verilogBits()

  local CR = C.generalizedChangeRate( inputBits, desiredTotalInputBits,1, 64,0,128*8  )

  local ChangeRateModule, totalBits = CR[1], CR[2]
  
  assert( Uniform(totalBits%(128*8)):eq(0):assertAlwaysTrue() )
  assert( Uniform(totalBits%inputBits):eq(0):assertAlwaysTrue() )
  assert( Uniform(totalBits%Uniform(16*64)):eq(0):assertAlwaysTrue() ) -- burst size is 128 bytes=1024 bits
  assert( Uniform(totalBits):ge(desiredTotalInputBits):assertAlwaysTrue() )

  if desiredTotalInputBits~=totalBits then
    out = RM.makeHandshake(C.arrayop(types.bits(inputBits),1))(out)
    out = RM.liftHandshake(RM.padSeq(types.bits(inputBits),desiredTotalInputBits/inputBits,1,1,0,(totalBits-desiredTotalInputBits)/inputBits,0,0,0))(out)
    out = RM.makeHandshake(C.index(types.array2d(types.bits(inputBits),1),0))(out)
  end

  out = ChangeRateModule(out)

  out = SOC.axiBurstWriteN( filename, totalBits/8, address, writeFn_orig )(out)

  local res = RM.lambda("WriteBurst_W"..W.."_H"..H.."_Vw"..Vw.."_Vh"..Vh.."_port"..SOC.currentMAXIWritePort.."_addr"..tostring(SOC.currentAddr).."_"..tostring(ty),inp,out,nil,nil,nil,globalMetadata)

  SOC.currentMAXIWritePort = SOC.currentMAXIWritePort+1
  if addressOverride==nil then
    SOC.currentAddr = SOC.currentAddr+totalBits:maximum()/8
    assert(type(SOC.currentAddr)=="number")
  else
    assert(type(SOC.currentAddr)=="number")
    SOC.currentAddr = math.max(SOC.currentAddr,address:maximum()+(totalBits:maximum()/8))
  end
  
  
  if framed then
    -- HACK
    if Vw==0 then
      res.inputType = types.RV(types.Seq(types.Par(inputType),W_orig,H_orig))
    else
      res.inputType = types.RV(types.ParSeq(types.array2d(ty,Vw,Vh),W_orig,H_orig))
    end
  end
  
  return res
end)


-- This works like C pointer deallocation:
-- input address N of type T actually reads at physical memory address N*sizeof(T)+base
-- syncAddrData: addr/data come in as one stream (default false)
SOC.write = J.memoize(function( filename, W_orig, H, writeType, V, syncAddrData, writeFn_orig, addressBase_orig, X)
  J.err( type(filename)=="string","SOC.write: filename must be string")
  J.err( types.isType(writeType), "SOC.write: type must be type")
  J.err( writeType:verilogBits()%8==0, "SOC.write: NYI - type must be byte aligned")
  if writeType:verilogBits()>64 then
    J.err( writeType:verilogBits()%64==0, "SOC.write: NYI - type must be 8 byte aligned")
  end
  if syncAddrData==nil then syncAddrData=false end
  assert( type(syncAddrData)=="boolean" )
  J.err( R.isFunction(writeFn_orig), "soc.write: writeFn should be rigel function, but is: ",writeFn_orig)
  local W = Uniform(W_orig)
  if V==nil then V=1 end

  local address
  if addressBase_orig~=nil then
    address = Uniform(addressBase_orig)
  else
    assert(type(SOC.currentAddr)=="number")
    address = SOC.currentAddr
  end
  
  local globalMetadata={}
  globalMetadata[writeFn_orig.name.."_write_address"] = address
  globalMetadata[writeFn_orig.name.."_write_W"] = W
  globalMetadata[writeFn_orig.name.."_write_H"] = H
  globalMetadata[writeFn_orig.name.."_write_V"] = V
  globalMetadata[writeFn_orig.name.."_write_type"] = tostring(writeType)
  globalMetadata[writeFn_orig.name.."_write_bitsPerPixel"] = writeType:verilogBits()

  if V>0 then writeType=types.array2d(writeType,V) end

  local inp, inpAddr, inpData

  local G = require "generators.core"

  if syncAddrData then
    inp = R.input( R.Handshake(types.tuple{types.uint(32),writeType}) )
    local tmp = G.FanOut{2}(inp)
    
    inpAddr = R.selectStream( "inpAddr", tmp, 0 )
    inpAddr = G.FIFO{128}(inpAddr)
    inpAddr = G.Index{0}(inpAddr)
    inpData = R.selectStream( "inpData", tmp, 1 )
    inpData = G.FIFO{128}(inpData)
    inpData = G.Index{1}(inpData)
  else
    inp = R.input( R.HandshakeTuple{types.uint(32),writeType} )

    inpAddr = R.selectStream( "inpAddr", inp, 0 )
    inpData = R.selectStream( "inpData", inp, 1 )
  end

  local writeBytesPerBurst
  
  -- scale by type size
  inpAddr = G.Mul{writeType:verilogBits()/8}(inpAddr)
  inpData = RM.makeHandshake(C.bitcast(writeType,types.bits(writeType:verilogBits())))(inpData)
  
  if writeType:verilogBits()/8 > 8*16 then
    assert(false) -- NYI
  else
    writeBytesPerBurst = writeType:verilogBits()/8
  end

  local out = SOC.axiWriteBytes( filename, writeBytesPerBurst, SOC.currentMAXIWritePort, address, writeFn_orig )(inpAddr,inpData)

  local N = writeType:verilogBits()/64
  
  if writeType:verilogBits()==64 then
    --out = RM.makeHandshake(C.bitcast(types.bits(64),writeType))(out)
  elseif writeType:verilogBits()>64 then
    assert(false) -- NYI - need to collect N triggers
  else
    assert(false)
  end

  local res = RM.lambda("Write_port"..SOC.currentMAXIWritePort.."_addr"..tostring(address).."_"..tostring(writeType),inp,out,nil,nil,nil,globalMetadata)
  
  SOC.currentMAXIWritePort = SOC.currentMAXIWritePort+1

  if addressBase_orig==nil then
    SOC.currentAddr = SOC.currentAddr+Uniform(Uniform(W)*Uniform(H)):maximum()
    assert(type(SOC.currentAddr)=="number")
  else
    SOC.currentAddr = Uniform(Uniform(SOC.currentAddr):max(address+(Uniform(W)*Uniform(H)))):maximum()
  end
  
  return res
end)

function SOC.export(t)
  if t==nil then t=_G end
  for k,v in pairs(SOC) do rawset(t,k,v) end
end


return SOC
