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

--SOCMT.doneHack = global(bool)

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

function SOCMT.axiRegs(mod,tab, readSource, readSink, writeSource, writeSink, X )
  local struct AxiRegsN { startReg:bool, done_ready:bool, start_ready:bool, doneReg:bool, RDATAReady:bool }

  for k,v in pairs(tab) do
    local ty = v[1]
    --print("ADDENTRY",k,v,ty,v[1],ty:toTerraType())
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
    readSource.terraCalculateReady(true)
    writeSource.terraCalculateReady(array(true,true))
  end

  local regSet = {}
  local regReady = {}

  local W = symbol(types.lower(AXI.WriteIssue(32)):toTerraType(),"W")
  
  for k,v in pairs(tab) do
    local addr = mod.globalMetadata["AddrOfRegister_regs_"..k]
    local ty = v[1]

    if v[3]=="input" then
      --assert(false)
      -- register inputs are always Handshaked
      --table.insert( regReady, quote [mod:getGlobal(k):terraReady()] = true; end )
    else
      for i=0,math.ceil(ty:verilogBits()/32)-1 do
        table.insert(regSet,
          quote
            if @AXIT.AWADDR32(&W)==[addr+i*4] then
--              cstdio.printf( "ACCEPT REG WRITE ADDR:%x, DATA:%d/0x%x\n", @AXIT.AWADDR32(&W), @AXIT.WDATA32(&W), @AXIT.WDATA32(&W) )
              @([&uint](&SELF.[k.."_value"])+i) = @AXIT.WDATA32(&W)
            end
          end)

      end
    end
  end

  AxiRegsN.methods.start = terra( [SELF], out : &bool )
    var [W] 
    writeSource.terraFn(&W)
  
    if @[AXIT.AWVALID(32)](&W) then
      --cstdio.printf("socTerra: WRITE TO REG. Addr:%x Data:%d\n",@AXIT.AWADDR32(&W),@AXIT.WDATA32(&W))

      var BRESP : types.lower(AXI.WriteResponse(32)):toTerraType()
      @AXIT.BRESP32(&BRESP) = 0
      @AXIT.BVALID32(&BRESP) = true
      [writeSink.terraFn](&BRESP)

      var addr = @AXIT.AWADDR32(&W)
      if addr==0xa0000000 then
        SELF.startReg = true
        SELF.doneReg = false
        cstdio.printf("socTerra.axiRegs: pipeline start requested, waiting on ready\n")
      else
        [regSet]
      end
    end

    @out = SELF.startReg

    if SELF.startReg and SELF.start_ready then
      cstdio.printf("socTerra.axiRegs: trigger pipeline start\n")
      SELF.startReg = false
    end
  end

  terra AxiRegsN:done( inp : &bool )
    var AR : types.lower(AXI.ReadAddress):toTerraType()
    readSource.terraFn(&AR)
    var RDATA : types.lower(AXI.ReadData(32)):toTerraType()
    
    if @AXIT.RVALID32(&RDATA) then
      @AXIT.RVALID32(&RDATA) = false
    end

    if @AXIT.ARVALID32(&AR) then
      if @AXIT.ARADDR32(&AR)~=0xa0000004 then
        cstdio.printf("socTerra: AxiRegsN: NYI - read from something other than done bit!\n")
      end
      
      @AXIT.RVALID32(&RDATA) = true
      @AXIT.RRESP32(&RDATA) = 0
      
      if self.doneReg then
        @AXIT.RDATA32(&RDATA) = 1
      else
        @AXIT.RDATA32(&RDATA) = 0
      end
    end
    
    if @inp then
      cstdio.printf("axiRegsN: PIPELINE DONE\n")
      self.doneReg = true
    end

    readSink.terraFn(&RDATA)
  end

  terra AxiRegsN:done_calculateReady()
    self.done_ready = true
    self.RDATAReady = readSink.terraReady
  end

  terra AxiRegsN:start_calculateReady(readyDownstream:bool)
    self.start_ready = readyDownstream
    [regReady]
  end

  return MT.new(AxiRegsN)
end

function SOCMT.axiBurstReadN( mod, totalBytes_orig, port, baseAddress_orig, readFn )
  --assert(type(baseAddress)=="number")
  local baseAddress = Uniform(baseAddress_orig)
  local totalBytes = Uniform(totalBytes_orig)
  assert( (totalBytes % 128):eq(0):assertAlwaysTrue() )

  local outputType = R.Handshake(types.bits(64))
  local struct ReadBurst { nextByteToRead:uint, ready:bool, bytesRead:uint, readyDownstream:bool }

  terra ReadBurst:reset()
    self.nextByteToRead = [totalBytes:toTerra()]
    self.bytesRead = 0
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
    elseif self.nextByteToRead<[totalBytes:toTerra()] and readFn.terraReady==false then
      cstdio.printf("readBurst: want to read, but ARREADY is false\n")
    elseif self.nextByteToRead>=[totalBytes:toTerra()] then
      valid(AR) = false
    else
      cstdio.printf("UNKNOWN READ BURST COND? %d\n",self.nextByteToRead)
    end

    readFn.terraFn(&AR,&RDATA)
      
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
    readFn.terraCalculateReady(readyDownstream)
    self.ready = readFn.terraReady
    self.readyDownstream = readyDownstream
  end

  return MT.new(ReadBurst)
end


function SOCMT.axiBurstWriteN( mod, Nbytes_orig, port, baseAddress_orig, writeFn )
  assert( R.isFunction(writeFn) )
  
  local baseAddress = Uniform(baseAddress_orig)
  local Nbytes = Uniform(Nbytes_orig)

  local struct WriteBurst { nextAddrToWrite:uint, ready:bool, addrReadyDownstream:bool, doneReg:bool, writtenBytes:uint, readyDownstream:bool, dataBuffer:uint64, writeFirst:bool }

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
      cstdio.printf("WRITEFIRST nextAddrToWrite:%d IP_MAXI_WDATA_READY:%d data:%d/%#x\n", self.nextAddrToWrite, writeFn.terraReady[1], self.dataBuffer, self.dataBuffer )
      @AXIT.WVALID64(&W) = (self.nextAddrToWrite>0)
      cstring.memcpy( AXIT.WDATA64(&W), &self.dataBuffer, [R.extractData(inputType):sizeof()] )

      if (self.nextAddrToWrite>0) and writeFn.terraReady[1] then
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

    writeFn.terraFn(&W,&BRESP)

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
    writeFn.terraCalculateReady(readyDownstream)
    self.ready = (writeFn.terraReady[1] or self.nextAddrToWrite==[Nbytes:toTerra()]) and (self.writeFirst==false);
    self.addrReadyDownstream = writeFn.terraReady[0]
    self.readyDownstream = readyDownstream
  end

  return MT.new(WriteBurst)
end

function SOCMT.axiReadBytes( mod, Nbytes, port, addressBase, readFn )
  assert(type(addressBase)=="number")
  assert(R.isFunction(readFn))
  
  local inputType = R.Handshake(types.uint(32))
  local outputType = R.Handshake(types.bits(64))

  local struct ReadBytes { ready:bool, ARADDRReady:bool, readyDownstream:bool }

  local burstCount = Nbytes/8
  J.err( burstCount<=16,"axiReadBytes: NYI - burst longer than 16")

  terra ReadBytes:reset()
    --[mod:getGlobal("IP_MAXI"..port.."_RDATA"):terraReady()] = false
    self.ready = true
  end

  terra ReadBytes:process( dataIn:&R.lower(inputType):toTerraType(), dataOut:&R.lower(outputType):toTerraType() )
    var AR : types.lower(AXI.ReadAddress64):toTerraType()
    var RDATA : types.lower(AXI.ReadData64):toTerraType()

    if valid(dataIn) and self.ready then
      var addr = data(dataIn)+[addressBase]
      --valid([mod:getGlobal("IP_MAXI"..port.."_ARADDR_RV"):terraValue()]) = true
      --data([mod:getGlobal("IP_MAXI"..port.."_ARADDR_RV"):terraValue()]) = addr
      --[mod:getGlobal("IP_MAXI"..port.."_ARLEN"):terraValue()] = [burstCount-1]
      --[mod:getGlobal("IP_MAXI"..port.."_ARSIZE"):terraValue()] = 3
      --[mod:getGlobal("IP_MAXI"..port.."_ARBURST"):terraValue()] = 1
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

    readFn.terraFn(&AR,&RDATA)
    
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
  --self.ARADDRReady = [mod:getGlobal("IP_MAXI"..port.."_ARADDR_RV"):terraReady()]
    readFn.terraCalculateReady(readyDownstream)
    --self.ARADDRReady = readFn.terraReady
    --[mod:getGlobal("IP_MAXI"..port.."_RDATA"):terraReady()] = readyDownstream
    self.readyDownstream = readyDownstream
    self.ready = readFn.terraReady
  end

  return MT.new(ReadBytes)
end

function SOCMT.axiWriteBytes( mod, Nbytes, port, addressBase_orig, writeFn )
  assert(R.isFunction(writeFn))
  
  local addressBase = Uniform(addressBase_orig)

  local Nbits = math.min(64,Nbytes*8)
  
  local inputType = R.HandshakeTuple{types.uint(32),types.bits(Nbits)}
  local outputType = R.HandshakeTrigger

  local struct WriteBytes { ready:bool[2] }
  
  local burstCount = Nbytes/8
  J.err( burstCount<=16,"axiReadBytes: NYI - burst longer than 16")

  terra WriteBytes:reset()
    --[mod:getGlobal("IP_MAXI"..port.."_WDATA_RV"):terraReady()] = false
    self.ready[0] = false
    self.ready[1] = false
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
    
    --data([mod:getGlobal("IP_MAXI"..port.."_AWADDR_RV"):terraValue()]) = data((@dataIn)._0) + [uint]([addressBase:toTerra()])
    --valid([mod:getGlobal("IP_MAXI"..port.."_AWADDR_RV"):terraValue()]) = valid((@dataIn)._0)
    --[mod:getGlobal("IP_MAXI"..port.."_WDATA_RV"):terraValue()] = (@dataIn)._1

    --[mod:getGlobal("IP_MAXI"..port.."_AWLEN"):terraValue()] = (burstCount-1)
    --[mod:getGlobal("IP_MAXI"..port.."_AWSIZE"):terraValue()] = 3
    --[mod:getGlobal("IP_MAXI"..port.."_AWBURST"):terraValue()] = 1
    --[mod:getGlobal("IP_MAXI"..port.."_WSTRB"):terraValue()] = 255

    writeFn.terraFn(&W,&BRESP)
    --@dataOut = valid([mod:getGlobal("IP_MAXI"..port.."_BRESP"):terraValue()])
    @dataOut = @AXIT.BVALID64(&BRESP)
  end

  terra WriteBytes:calculateReady(readyDownstream:bool)
    --cstdio.printf("READBUSRT CALCReADY\n")
  --[mod:getGlobal("IP_MAXI"..port.."_BRESP"):terraReady()] = readyDownstream
    writeFn.terraCalculateReady(readyDownstream)
    --self.ready[0] = [mod:getGlobal("IP_MAXI"..port.."_AWADDR_RV"):terraReady()]
    --self.ready[1] = [mod:getGlobal("IP_MAXI"..port.."_WDATA_RV"):terraReady()]
    self.ready = writeFn.terraReady
  end

  return MT.new(WriteBytes)
end

return SOCMT
