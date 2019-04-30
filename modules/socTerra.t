local R = require "rigel"
local MT = require "modulesTerra"
local types = require "types"
local cstdio = terralib.includec("stdio.h")
local cstdlib = terralib.includec("stdlib.h")
local cstring = terralib.includec("string.h")
local J = require "common"
local Uniform = require "uniform"
local AXI = require "axi"
local AXIT = require "axiTerra"

local data = macro(function(i) return `i._0 end)
local valid = macro(function(i) return `i._1 end)

local SOCMT = {}

function SOCMT.regStub(tab)
  local struct RegStub {}

  for regname,v in pairs(tab) do
    local regtype = v[1]
    local regval = v[2]
    print("REGSTUB",regname)
    RegStub.methods[regname] = terra( self:&RegStub, out: &regtype:toTerraType())
      @out = [regtype:valueToTerra(regval)]
    end
  end

  return MT.new(RegStub)
end

function SOCMT.axiRegs( mod, tab, X )
  assert(X==nil)
  local struct AxiRegsN { startReg:bool, done_ready:bool, start_ready:bool, doneReg:bool, reading:bool, read_readyDownstream:bool, read_ready:bool, write_ready:bool[2], write_readyDownstream:bool }

  for k,v in pairs(tab) do
    local ty = v[1]

    table.insert( AxiRegsN.entries,{field=k.."_value",type=ty:toTerraType()})

    if v[3]=="input" then
      table.insert( AxiRegsN.entries,{field=k.."_ready",type=bool})
    end
  end

  local SELF = symbol(&AxiRegsN)
  
  for k,v in pairs(tab) do
    local ty = v[1]

    if v[3]=="input" then
      AxiRegsN.methods[k] = terra([SELF],inp:&types.lower(types.Handshake(ty)):toTerraType())
        if valid(@inp) then SELF.[k.."_value"] = data(@inp) end
      end
      AxiRegsN.methods[k.."_calculateReady"] = terra([SELF]) SELF.[k.."_ready"] = true; end
    else
      AxiRegsN.methods[k] = terra([SELF],out:&ty:toTerraType())
        @out=SELF.[k.."_value"]
      end
    end
  end
  
  terra AxiRegsN:reset()
    self.startReg = false
    self.doneReg = false
    self.reading = false
  end

  local regSet = {}
  local regReady = {}

  AxiRegsN.methods.start = terra( [SELF], out : &bool )
    @out = SELF.startReg

    if SELF.startReg and SELF.start_ready then
      cstdio.printf("socTerra.axiRegs: trigger pipeline start\n")
      SELF.startReg = false
    end
  end

  local writeInp = symbol(&types.lower(AXI.WriteIssue(32)):toTerraType(),"writeInp")
  
  for k,v in pairs(tab) do
    local addr = mod.globalMetadata["AddrOfRegister_InstCall_regs_"..k]
    local ty = v[1]

    if v[3]=="input" then
    else
      for i=0,math.ceil(ty:verilogBits()/32)-1 do
        table.insert(regSet,
          quote
            if @AXIT.AWADDR32(writeInp)==[addr+i*4] then
--              cstdio.printf( "ACCEPT REG WRITE ADDR:%x, DATA:%d/0x%x\n", @AXIT.AWADDR32(&W), @AXIT.WDATA32(&W), @AXIT.WDATA32(&W) )
              @([&uint](&SELF.[k.."_value"])+i) = @AXIT.WDATA32(writeInp)
            end
          end)

      end
    end
  end

  terra AxiRegsN.methods.write( [SELF], [writeInp], BRESP: &types.lower(AXI.WriteResponse(32)):toTerraType() )
    if @[AXIT.AWVALID(32)](writeInp) then
      --cstdio.printf("socTerra: WRITE TO REG. Addr:%x Data:%d\n",@AXIT.AWADDR32(&W),@AXIT.WDATA32(&W))

      @AXIT.BRESP32(BRESP) = 0
      @AXIT.BVALID32(BRESP) = true

      var addr = @AXIT.AWADDR32(writeInp)
      if addr==0xa0000000 then
        SELF.startReg = true
        SELF.doneReg = false
        cstdio.printf("socTerra.axiRegs: pipeline start requested, waiting on ready\n")
      else
        [regSet]
      end
    end

  end

  terra AxiRegsN:write_calculateReady(readyDownstream:bool)
    self.write_ready[0] = true
    self.write_ready[1] = true
    self.write_readyDownstream = readyDownstream
  end

  terra AxiRegsN:done( inp : &bool )
    if @inp then
      cstdio.printf("axiRegsN: PIPELINE DONE\n")
      self.doneReg = true
    end
  end

  terra AxiRegsN:read( inp : &types.lower(AXI.ReadAddress32):toTerraType(), out:&types.lower(AXI.ReadData(32)):toTerraType()  )
    if @AXIT.ARVALID32(inp) then
      if @AXIT.ARADDR32(inp)~=0xa0000004 then
        cstdio.printf("socTerra: AxiRegsN: NYI - read from something other than done bit!\n")
      end

      self.reading = true
    end

    if self.reading then
      @AXIT.RVALID32(out) = true
      @AXIT.RRESP32(out) = 0
      
      if self.doneReg then
        @AXIT.RDATA32(out) = 1
      else
        @AXIT.RDATA32(out) = 0
      end
      if self.read_ready then
        self.reading = false
      end
    else
      @AXIT.RVALID32(out) = false
    end
  end

  terra AxiRegsN:read_calculateReady(readyDownstream:bool)
    self.read_ready = true
    self.read_readyDownstream = readyDownstream
  end

  terra AxiRegsN:done_calculateReady()
    self.done_ready = true
  end

  terra AxiRegsN:start_calculateReady(readyDownstream:bool)
    self.start_ready = readyDownstream
    [regReady]
  end

  return MT.new(AxiRegsN)
end

function SOCMT.axiBurstReadN( mod, totalBytes_orig, baseAddress_orig, rigelReadFn, X )
  assert(X==nil)
  --assert(type(baseAddress)=="number")
  local baseAddress = Uniform(baseAddress_orig)
  local totalBytes = Uniform(totalBytes_orig)
  assert( (totalBytes % 128):eq(0):assertAlwaysTrue() )

  local outputType = R.Handshake(types.bits(64))
  local struct ReadBurst { readFn:rigelReadFn.terraModule, nextByteToRead:uint, ready:bool, bytesRead:uint, readyDownstream:bool }

  terra ReadBurst:init() self.readFn:init() end
  terra ReadBurst:free() self.readFn:free() end

  terra ReadBurst:reset()
    self.nextByteToRead = [totalBytes:toTerra()]
    self.bytesRead = 0
    self.readFn:reset()
  end

  terra ReadBurst:process( trigger:&bool, dataOut:&R.lower(outputType):toTerraType() )
    if @trigger and self.nextByteToRead >= [totalBytes:toTerra()] then
      self.nextByteToRead = 0
      self.bytesRead = 0
    end

    var AR : types.lower(AXI.ReadAddress64):toTerraType()
    var RDATA : types.lower(AXI.ReadData64):toTerraType()
          
    if self.nextByteToRead<[totalBytes:toTerra()] then
      var addr = self.nextByteToRead+[baseAddress:toTerra()]
      
      valid(AR) = true
      @AXIT.ARADDR(&AR) = addr
      @AXIT.ARLEN(&AR) = 15
      @AXIT.ARSIZE(&AR) = 3
      @AXIT.ARBURST(&AR) = 1
      
      if self.ready then
        self.nextByteToRead = self.nextByteToRead + 128
      end
    elseif self.nextByteToRead<[totalBytes:toTerra()] and self.readFn.ready==false then
      cstdio.printf("readBurst: want to read, but ARREADY is false\n")
    elseif self.nextByteToRead>=[totalBytes:toTerra()] then
      valid(AR) = false
    else
      cstdio.printf("UNKNOWN READ BURST COND? %d\n",self.nextByteToRead)
    end

    self.readFn:process(&AR,&RDATA)
      
    if valid(RDATA) then
      cstring.memcpy( &data(dataOut), AXIT.RDATA64(&RDATA), [R.extractData(outputType):sizeof()] )
      valid(dataOut) = true
      
      if self.readyDownstream then
        self.bytesRead = self.bytesRead+8

        if self.bytesRead>self.nextByteToRead then
          cstdio.printf("socTerra: READ TOO MUCH? readBurst has recieved more data than addresses sent. bytesRead:%d nextByteToRead:%d\n",self.bytesRead,self.nextByteToRead)
          cstdlib.exit(1)
        end
      end
    else
      valid(dataOut) = false
    end

  end

  terra ReadBurst:calculateReady(readyDownstream:bool)
    self.readFn:calculateReady(readyDownstream)
    self.ready = self.readFn.ready
    self.readyDownstream = readyDownstream
  end

  return MT.new(ReadBurst)
end


function SOCMT.axiBurstWriteN( mod, Nbytes_orig, baseAddress_orig, writeFn )
  assert( R.isFunction(writeFn) )
  
  local baseAddress = Uniform(baseAddress_orig)
  local Nbytes = Uniform(Nbytes_orig)

  local struct WriteBurst { nextAddrToWrite:uint, ready:bool, addrReadyDownstream:bool, doneReg:bool, writtenBytes:uint, readyDownstream:bool, dataBuffer:uint64, writeFirst:bool, writeFnInst:writeFn.terraModule }

  local inputType = R.Handshake(types.bits(64))
  
  terra WriteBurst:reset()
    self.nextAddrToWrite = [Nbytes:toTerra()]
    self.doneReg = true
    self.writtenBytes = [Nbytes:toTerra()]
    self.writeFirst = false
  end

  terra WriteBurst:process( dataIn:&R.lower(inputType):toTerraType(), done:&bool )
    var W : types.lower(AXI.WriteIssue64):toTerraType()
    var BRESP : types.lower(AXI.WriteResponse64):toTerraType()
  
    if valid(dataIn) and self.nextAddrToWrite==[Nbytes:toTerra()] and self.writtenBytes==[Nbytes:toTerra()] and self.writeFirst==false then
      -- starting
      cstdio.printf("BurstWrite: start to send addresses nextAddrToWrite:%d valid:%d data:%d/%#x\n",self.nextAddrToWrite,valid(dataIn),data(dataIn),data(dataIn))

      self.nextAddrToWrite = 0
      self.dataBuffer = data(dataIn)
      self.doneReg = false
      self.writeFirst = true
      self.writtenBytes = 0
      
      @AXIT.WVALID64(&W) = false
    elseif self.writeFirst then
      cstdio.printf("WRITEFIRST nextAddrToWrite:%d IP_MAXI_WDATA_READY:%d data:%d/%#x\n", self.nextAddrToWrite, self.writeFnInst.ready[1], self.dataBuffer, self.dataBuffer )
      @AXIT.WVALID64(&W) = (self.nextAddrToWrite>0)
      cstring.memcpy( AXIT.WDATA64(&W), &self.dataBuffer, [R.extractData(inputType):sizeof()] )

      if (self.nextAddrToWrite>0) and self.writeFnInst.ready[1] then
        self.writeFirst=false
      end
    elseif valid(dataIn) and self.nextAddrToWrite>0 then
      @AXIT.WVALID64(&W) = true
      cstring.memcpy( AXIT.WDATA64(&W), &data(dataIn), [R.extractData(inputType):sizeof()] )
    else
      @AXIT.WVALID64(&W) = false
      if self.ready and valid(dataIn) then
        cstdio.printf("Internal ERROR: we're ready and valid, but no write is occuring?\n")
        cstdlib.exit(1)
      end
    end

    if self.nextAddrToWrite<[Nbytes:toTerra()] then
      var addr = self.nextAddrToWrite+[baseAddress:toTerra()]
      
      @AXIT.AWVALID64(&W) = true
      @AXIT.AWADDR64(&W) = addr
      
      @AXIT.AWLEN64(&W) = 15
      @AXIT.AWSIZE64(&W) = 3
      @AXIT.AWBURST64(&W) = 1
      @AXIT.WSTRB64(&W) = 255
      
      if self.addrReadyDownstream then
        self.nextAddrToWrite = self.nextAddrToWrite + 128
      end
    else
      @AXIT.AWVALID64(&W) = false
    end

    self.writeFnInst:process(&W,&BRESP)

    if @AXIT.BVALID64(&BRESP) then
      if self.readyDownstream then
        self.writtenBytes = self.writtenBytes + 128

        if self.writtenBytes>self.nextAddrToWrite then
          cstdio.printf("WROTE TOO MUCH? writtenBytes:%d  nextAddrToWrite:%d totalBytes:%d\n",self.writtenBytes, self.nextAddrToWrite,[Nbytes:toTerra()])
          cstdlib.exit(1)
        end
      else
        cstdio.printf("Internal ERROR: ready should be true? AA\n")
        cstdlib.exit(1)
      end
    end
    
    @done = (self.writtenBytes==[Nbytes:toTerra()]) and (self.doneReg==false)

    if (self.writtenBytes==[Nbytes:toTerra()]) and self.readyDownstream then
      self.doneReg = true
    end
  end

  terra WriteBurst:calculateReady(readyDownstream:bool)
    -- ready needs to be true at the start of time (b/c WDATA may not be true until it sees addresses)
    -- but ready needs to be false once we've seen 1 valid, but not written it to bus
    self.writeFnInst:calculateReady(readyDownstream)
    self.ready = (self.writeFnInst.ready[1] or self.nextAddrToWrite==[Nbytes:toTerra()]) and (self.writeFirst==false);
    self.addrReadyDownstream = self.writeFnInst.ready[0]
    self.readyDownstream = readyDownstream
  end

  return MT.new(WriteBurst)
end

function SOCMT.axiReadBytes( mod, Nbytes, port, addressBase_orig, readFn )
  assert(R.isFunction(readFn))

  local addressBase = Uniform(addressBase_orig)
  
  local inputType = R.Handshake(types.uint(32))
  local outputType = R.Handshake(types.bits(64))

  local struct ReadBytes { ready:bool, ARADDRReady:bool, readyDownstream:bool, readFnInst:readFn.terraModule }

  local burstCount = Nbytes/8
  J.err( burstCount<=16,"axiReadBytes: NYI - burst longer than 16")

  terra ReadBytes:init()
    self.readFnInst:init()
  end

  terra ReadBytes:reset()
    self.ready = true
    self.readFnInst:reset()
  end

  terra ReadBytes:process( dataIn:&R.lower(inputType):toTerraType(), dataOut:&R.lower(outputType):toTerraType() )
    var AR : types.lower(AXI.ReadAddress64):toTerraType()
    var RDATA : types.lower(AXI.ReadData64):toTerraType()

    if valid(dataIn) and self.ready then
      var addr = data(dataIn)+[addressBase:toTerra()]

      valid(AR) = true
      @AXIT.ARADDR(&AR) = addr
      @AXIT.ARLEN(&AR) = [burstCount-1]
      @AXIT.ARSIZE(&AR) = 3
      @AXIT.ARBURST(&AR) = 1
    elseif valid(dataIn) and self.ARADDRReady==false then
      cstdio.printf("readBytes: want to read, but ARREADY is false\n")
    elseif valid(dataIn)==false and self.ARADDRReady then
      valid(AR) = false
    end

    self.readFnInst:process(&AR,&RDATA)
    
    if self.readyDownstream then
      if valid(RDATA) then
        cstring.memcpy( &data(dataOut), AXIT.RDATA64(&RDATA), [R.extractData(outputType):sizeof()] )
        valid(dataOut) = true
      else
        valid(dataOut) = false
      end
    end
  end

  terra ReadBytes:calculateReady(readyDownstream:bool)
    self.readFnInst:calculateReady(readyDownstream)
    self.readyDownstream = readyDownstream
    self.ready = self.readFnInst.ready
  end

  return MT.new(ReadBytes)
end

function SOCMT.axiWriteBytes( mod, Nbytes, port, addressBase_orig, writeFn )
  assert(R.isFunction(writeFn))
  
  local addressBase = Uniform(addressBase_orig)

  local Nbits = math.min(64,Nbytes*8)
  
  local inputType = R.HandshakeTuple{types.uint(32),types.bits(Nbits)}
  local outputType = R.HandshakeTrigger

  local struct WriteBytes { ready:bool[2], writeFnInst:writeFn.terraModule }
  
  local burstCount = Nbytes/8
  J.err( burstCount<=16,"axiReadBytes: NYI - burst longer than 16")

  terra WriteBytes:reset()
    self.ready[0] = false
    self.ready[1] = false
    self.writeFnInst:reset()
  end

  terra WriteBytes:init()
    self.writeFnInst:init()
  end

  terra WriteBytes:process( dataIn:&R.lower(inputType):toTerraType(), dataOut:&R.lower(outputType):toTerraType() )
    var W : types.lower(AXI.WriteIssue64):toTerraType()
    var BRESP : types.lower(AXI.WriteResponse64):toTerraType()

    @AXIT.AWVALID64(&W) = valid((@dataIn)._0)
    @AXIT.AWADDR64(&W) = data((@dataIn)._0) + [uint]([addressBase:toTerra()])
    @AXIT.AWLEN64(&W) = (burstCount-1)
    @AXIT.AWSIZE64(&W) = 3
    @AXIT.AWBURST64(&W) = 1

    @AXIT.WVALID64(&W) = valid((@dataIn)._1)
    @AXIT.WDATA64(&W) = data((@dataIn)._1)
    @AXIT.WSTRB64(&W) = 255

    self.writeFnInst:process(&W,&BRESP)
    @dataOut = @AXIT.BVALID64(&BRESP)
  end

  terra WriteBytes:calculateReady(readyDownstream:bool)
    self.writeFnInst:calculateReady(readyDownstream)
    self.ready = self.writeFnInst.ready
  end

  return MT.new(WriteBytes)
end

return SOCMT
