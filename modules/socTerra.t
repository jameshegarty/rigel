local R = require "rigel"
local MT = require "modulesTerra"
local types = require "types"
local cstdio = terralib.includec("stdio.h")
local cstdlib = terralib.includec("stdlib.h")
local cstring = terralib.includec("string.h")
local J = require "common"
local Uniform = require "uniform"

local data = macro(function(i) return `i._0 end)
local valid = macro(function(i) return `i._1 end)

local SOCMT = {}

--SOCMT.doneHack = global(bool)

function SOCMT.axiRegs(mod,tab,port)
  local struct AxiRegsN { startReg:bool, doneReady:bool, startReady:bool, doneReg:bool, RDATAReady:bool }

  terra AxiRegsN:reset()
    self.startReg = false
    self.doneReg = false
    [mod:getGlobal("IP_SAXI"..port.."_ARADDR"):terraReady()] = true
    [mod:getGlobal("IP_SAXI"..port.."_AWADDR"):terraReady()] = true
    [mod:getGlobal("IP_SAXI"..port.."_WDATA"):terraReady()] = true
--    [SOCMT.doneHack] = false
  end

  local regSet = {}
  local regReady = {}
  
  for k,v in pairs(tab) do
    local addr = mod.globalMetadata["AddrOfRegister_"..k]
    local ty = mod.globalMetadata["TypeOfRegister_"..k]
    local glob = mod:getGlobal(k):terraValue()

    if v[3]=="input" then
      -- register inputs are always Handshaked
      table.insert( regReady, quote [mod:getGlobal(k):terraReady()] = true; end )
    else
      for i=0,math.ceil(ty:verilogBits()/32)-1 do
        table.insert(regSet,
          quote
            if data([mod:getGlobal("IP_SAXI"..port.."_AWADDR"):terraValue()])==[addr+i*4] then
              cstdio.printf( "ACCEPT REG WRITE ADDR:%x, DATA:%d\n", data([mod:getGlobal("IP_SAXI"..port.."_AWADDR"):terraValue()]), data([mod:getGlobal("IP_SAXI"..port.."_WDATA"):terraValue()]) )
              @([&uint](&[glob])+i) = data([mod:getGlobal("IP_SAXI"..port.."_WDATA"):terraValue()])
            end
          end)
      end
    end
  end

  terra AxiRegsN:start( out : &bool )
    if valid([mod:getGlobal("IP_SAXI"..port.."_AWADDR"):terraValue()]) then
      cstdio.printf("WRITE TO REG %x\n",[mod:getGlobal("IP_SAXI"..port.."_AWADDR"):terraValue()])
      data([mod:getGlobal("IP_SAXI"..port.."_BRESP"):terraValue()]) = 0
      valid([mod:getGlobal("IP_SAXI"..port.."_BRESP"):terraValue()]) = true

      var addr = data([mod:getGlobal("IP_SAXI"..port.."_AWADDR"):terraValue()])
      if addr==0xa0000000 then
        self.startReg = true
        self.doneReg = false
      else
        [regSet]
      end
    end

    @out = self.startReg

    if self.startReg and self.startReady then
      self.startReg = false
    end
  end

  terra AxiRegsN:done( inp : &bool )

    if valid([mod:getGlobal("IP_SAXI"..port.."_RDATA"):terraValue()]) and self.RDATAReady then
      valid([mod:getGlobal("IP_SAXI"..port.."_RDATA"):terraValue()]) = false
    end

    if valid([mod:getGlobal("IP_SAXI"..port.."_ARADDR"):terraValue()]) then
      valid([mod:getGlobal("IP_SAXI"..port.."_RDATA"):terraValue()]) = true
      if self.doneReg then
        data([mod:getGlobal("IP_SAXI"..port.."_RDATA"):terraValue()]) = 1
      else
        data([mod:getGlobal("IP_SAXI"..port.."_RDATA"):terraValue()]) = 0
      end
    end
    
    if @inp then
      cstdio.printf("axiRegsN: PIPELINE DONE\n")
--      [SOCMT.doneHack] = true
      self.doneReg = true
    end
  end

  terra AxiRegsN:calculateDoneReady()
    --cstdio.printf("axiRegsN: calcDoneReady\n")
    self.doneReady = true
    self.RDATAReady = [mod:getGlobal("IP_SAXI"..port.."_RDATA"):terraReady()]
    [mod:getGlobal("IP_SAXI"..port.."_ARADDR"):terraReady()] = true
  end

  terra AxiRegsN:calculateStartReady(readyDownstream:bool)
    --cstdio.printf("axiRegsN: calcStartReady %d\n", readyDownstream)
    self.startReady = readyDownstream
    [regReady]
  end

  return MT.new(AxiRegsN)
end

function SOCMT.axiBurstReadN( mod, totalBytes_orig, port, baseAddress_orig )
  --assert(type(baseAddress)=="number")
  local baseAddress = Uniform(baseAddress_orig)
  local totalBytes = Uniform(totalBytes_orig)
  assert( (totalBytes % 128):eq(0):assertAlwaysTrue() )

  local outputType = R.Handshake(types.bits(64))
  local struct ReadBurst { nextByteToRead:uint, ready:bool, bytesRead:uint, readyDownstream:bool, addrReadyDownstream:bool }

  terra ReadBurst:reset()
    self.nextByteToRead = [totalBytes:toTerra()]
    [mod:getGlobal("IP_MAXI"..port.."_RDATA"):terraReady()] = true
    self.ready = true
    self.bytesRead = 0
  end

  terra ReadBurst:process( trigger:&bool, dataOut:&R.lower(outputType):toTerraType() )
    if @trigger and self.nextByteToRead >= [totalBytes:toTerra()] then
      --cstdio.printf("READ BURST START\n")
      self.nextByteToRead = 0
      self.bytesRead = 0
    end

    if self.nextByteToRead<[totalBytes:toTerra()] then
      var addr = self.nextByteToRead+[baseAddress:toTerra()]
      --cstdio.printf("readBurst: send address %d port %d ready %d\n",self.nextByteToRead, port, [mod:getGlobal("IP_MAXI"..port.."_ARADDR"):terraReady()])
      valid([mod:getGlobal("IP_MAXI"..port.."_ARADDR"):terraValue()]) = true
      data([mod:getGlobal("IP_MAXI"..port.."_ARADDR"):terraValue()]) = addr
      [mod:getGlobal("IP_MAXI"..port.."_ARLEN"):terraValue()] = 15
      [mod:getGlobal("IP_MAXI"..port.."_ARSIZE"):terraValue()] = 3
      [mod:getGlobal("IP_MAXI"..port.."_ARBURST"):terraValue()] = 1

      if self.addrReadyDownstream then
        self.nextByteToRead = self.nextByteToRead + 128
        --cstdio.printf("READBURST: inc addr %d\n",self.nextByteToRead)
      end
    elseif self.nextByteToRead<[totalBytes:toTerra()] and [mod:getGlobal("IP_MAXI"..port.."_ARADDR"):terraReady()]==false then
      cstdio.printf("readBurst: want to read, but ARREADY is false\n")
    elseif self.nextByteToRead>=[totalBytes:toTerra()] then
      valid([mod:getGlobal("IP_MAXI"..port.."_ARADDR"):terraValue()]) = false
    else
      cstdio.printf("UNKNOWN READ BURST COND? %d\n",self.nextByteToRead)
    end

    if valid([mod:getGlobal("IP_MAXI"..port.."_RDATA"):terraValue()]) then
      cstring.memcpy( &data(dataOut), &data([mod:getGlobal("IP_MAXI"..port.."_RDATA"):terraValue()]), [R.extractData(outputType):sizeof()] )
      valid(dataOut) = true
      


      if self.readyDownstream then
        self.bytesRead = self.bytesRead+8

        if self.bytesRead>self.nextByteToRead then
          cstdio.printf("READ TOO MUCH?\n")
        end
      end
    else
      valid(dataOut) = false
    end

  end

  terra ReadBurst:calculateReady(readyDownstream:bool)
  --cstdio.printf("READBUSRT CALCReADY\n")
--  cstdio.printf("READBURSTREADY %d\n",readyDownstream)
    [mod:getGlobal("IP_MAXI"..port.."_RDATA"):terraReady()] = readyDownstream

    --if readyDownstream==false then
    --  cstdio.printf("AXIBURSTREADN not ready DS\n")
    --end
  
    self.addrReadyDownstream = [mod:getGlobal("IP_MAXI"..port.."_ARADDR"):terraReady()];
    self.readyDownstream = readyDownstream
  end

  return MT.new(ReadBurst)
end


function SOCMT.axiBurstWriteN( mod, Nbytes_orig, port, baseAddress_orig )
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
    if valid(dataIn) and self.nextAddrToWrite==[Nbytes:toTerra()] and self.writtenBytes==[Nbytes:toTerra()] and self.writeFirst==false then
      -- starting
      cstdio.printf("BurstWrite: start to send addresses nextAddrToWrite:%d valid:%d data:%d/%#x\n",self.nextAddrToWrite,valid(dataIn),data(dataIn),data(dataIn))

      self.nextAddrToWrite = 0
      self.dataBuffer = data(dataIn)
      self.doneReg = false
      self.writeFirst = true
      self.writtenBytes = 0
      
      valid([mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraValue()]) = false
    elseif self.writeFirst then
      cstdio.printf("WRITEFIRST nextAddrToWrite:%d IP_MAXI_WDATA_READY:%d data:%d/%#x\n",self.nextAddrToWrite,[mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraReady()],self.dataBuffer,self.dataBuffer)
      valid([mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraValue()]) = (self.nextAddrToWrite>0)
      cstring.memcpy( &data([mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraValue()]), &self.dataBuffer, [R.extractData(inputType):sizeof()] )

      if (self.nextAddrToWrite>0) and [mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraReady()] then
        self.writeFirst=false
        self.writtenBytes = self.writtenBytes + 8
      end
    elseif valid(dataIn) and self.nextAddrToWrite>0 then
      valid([mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraValue()]) = true

      cstring.memcpy( &data([mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraValue()]), &data(dataIn), [R.extractData(inputType):sizeof()] )

      if self.ready then
        self.writtenBytes = self.writtenBytes + 8

        if self.writtenBytes>self.nextAddrToWrite then
          cstdio.printf("WROTE TOO MUCH? writtenBytes:%d  nextAddrToWrite:%d totalBytes:%d\n",self.writtenBytes, self.nextAddrToWrite,[Nbytes:toTerra()])
          cstdlib.exit(1)
        end
      else
        cstdio.printf("Internal ERROR: ready should be true? AA\n")
        cstdlib.exit(1)
      end
    else
      valid([mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraValue()]) = false
      if self.ready and valid(dataIn) then
        cstdio.printf("Internal ERROR: we're ready and valid, but no write is occuring?\n")
        cstdlib.exit(1)
      end
    end

    if self.nextAddrToWrite<[Nbytes:toTerra()] then
      var addr = self.nextAddrToWrite+[baseAddress:toTerra()]
      
      valid([mod:getGlobal("IP_MAXI"..port.."_AWADDR"):terraValue()]) = true
      data([mod:getGlobal("IP_MAXI"..port.."_AWADDR"):terraValue()]) = addr

      [mod:getGlobal("IP_MAXI"..port.."_AWLEN"):terraValue()] = 15
      [mod:getGlobal("IP_MAXI"..port.."_AWSIZE"):terraValue()] = 3
      [mod:getGlobal("IP_MAXI"..port.."_AWBURST"):terraValue()] = 1
      [mod:getGlobal("IP_MAXI"..port.."_WSTRB"):terraValue()] = 255

      if self.addrReadyDownstream then
        self.nextAddrToWrite = self.nextAddrToWrite + 128
      end
    else
      valid([mod:getGlobal("IP_MAXI"..port.."_AWADDR"):terraValue()]) = false
    end

    @done = (self.writtenBytes==[Nbytes:toTerra()]) and (self.doneReg==false)

    if (self.writtenBytes==[Nbytes:toTerra()]) and self.readyDownstream then
      self.doneReg = true
    end
  end

  terra WriteBurst:calculateReady(readyDownstream:bool)
    -- ready needs to be true at the start of time (b/c WDATA may not be true until it sees addresses)
    -- but ready needs to be false once we've seen 1 valid, but not written it to bus
    self.ready = ([mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraReady()] or self.nextAddrToWrite==[Nbytes:toTerra()]) and (self.writeFirst==false);
    
    self.addrReadyDownstream = [mod:getGlobal("IP_MAXI"..port.."_AWADDR"):terraReady()];

    self.readyDownstream = readyDownstream
    [mod:getGlobal("IP_MAXI"..port.."_BRESP"):terraReady()] = true
  end

  return MT.new(WriteBurst)
end

function SOCMT.axiReadBytes( mod, Nbytes, port, addressBase )
  assert(type(addressBase)=="number")

  local inputType = R.Handshake(types.uint(32))
  local outputType = R.Handshake(types.bits(64))

  local struct ReadBytes { ready:bool, ARADDRReady:bool, readyDownstream:bool }

  local burstCount = Nbytes/8
  J.err( burstCount<=16,"axiReadBytes: NYI - burst longer than 16")

  terra ReadBytes:reset()
    [mod:getGlobal("IP_MAXI"..port.."_RDATA"):terraReady()] = false
    self.ready = true
  end

  terra ReadBytes:process( dataIn:&R.lower(inputType):toTerraType(), dataOut:&R.lower(outputType):toTerraType() )

    if valid(dataIn) and self.ARADDRReady then
      var addr = data(dataIn)+[addressBase]
      valid([mod:getGlobal("IP_MAXI"..port.."_ARADDR_RV"):terraValue()]) = true
      data([mod:getGlobal("IP_MAXI"..port.."_ARADDR_RV"):terraValue()]) = addr
      [mod:getGlobal("IP_MAXI"..port.."_ARLEN"):terraValue()] = [burstCount-1]
      [mod:getGlobal("IP_MAXI"..port.."_ARSIZE"):terraValue()] = 3
      [mod:getGlobal("IP_MAXI"..port.."_ARBURST"):terraValue()] = 1
    elseif valid(dataIn) and self.ARADDRReady==false then
      cstdio.printf("readBytes: want to read, but ARREADY is false\n")
    elseif valid(dataIn)==false and self.ARADDRReady then
      valid([mod:getGlobal("IP_MAXI"..port.."_ARADDR_RV"):terraValue()]) = false
    end

    if self.readyDownstream then
      if valid([mod:getGlobal("IP_MAXI"..port.."_RDATA"):terraValue()]) then
        cstring.memcpy( &data(dataOut), &data([mod:getGlobal("IP_MAXI"..port.."_RDATA"):terraValue()]), [R.extractData(outputType):sizeof()] )
        valid(dataOut) = true
      else
        valid(dataOut) = false
      end
    end
  end

  terra ReadBytes:calculateReady(readyDownstream:bool)
    self.ARADDRReady = [mod:getGlobal("IP_MAXI"..port.."_ARADDR_RV"):terraReady()]
    [mod:getGlobal("IP_MAXI"..port.."_RDATA"):terraReady()] = readyDownstream
    self.readyDownstream = readyDownstream
    self.ready = [mod:getGlobal("IP_MAXI"..port.."_ARADDR_RV"):terraReady()]
  end

  return MT.new(ReadBytes)
end

function SOCMT.axiWriteBytes( mod, Nbytes, port, addressBase_orig )
  local addressBase = Uniform(addressBase_orig)

  local Nbits = math.min(64,Nbytes*8)
  
  local inputType = R.HandshakeTuple{types.uint(32),types.bits(Nbits)}
  local outputType = R.HandshakeTrigger

  local struct WriteBytes { ready:bool[2] }
  
  local burstCount = Nbytes/8
  J.err( burstCount<=16,"axiReadBytes: NYI - burst longer than 16")

  terra WriteBytes:reset()
    [mod:getGlobal("IP_MAXI"..port.."_WDATA_RV"):terraReady()] = false
    self.ready[0] = false
    self.ready[1] = false
  end

  terra WriteBytes:process( dataIn:&R.lower(inputType):toTerraType(), dataOut:&R.lower(outputType):toTerraType() )
    data([mod:getGlobal("IP_MAXI"..port.."_AWADDR_RV"):terraValue()]) = data((@dataIn)._0) + [uint]([addressBase:toTerra()])
    valid([mod:getGlobal("IP_MAXI"..port.."_AWADDR_RV"):terraValue()]) = valid((@dataIn)._0)
    [mod:getGlobal("IP_MAXI"..port.."_WDATA_RV"):terraValue()] = (@dataIn)._1

    [mod:getGlobal("IP_MAXI"..port.."_AWLEN"):terraValue()] = (burstCount-1)
    [mod:getGlobal("IP_MAXI"..port.."_AWSIZE"):terraValue()] = 3
    [mod:getGlobal("IP_MAXI"..port.."_AWBURST"):terraValue()] = 1
    [mod:getGlobal("IP_MAXI"..port.."_WSTRB"):terraValue()] = 255

    @dataOut = valid([mod:getGlobal("IP_MAXI"..port.."_BRESP"):terraValue()])
  end

  terra WriteBytes:calculateReady(readyDownstream:bool)
    --cstdio.printf("READBUSRT CALCReADY\n")
    [mod:getGlobal("IP_MAXI"..port.."_BRESP"):terraReady()] = readyDownstream
    self.ready[0] = [mod:getGlobal("IP_MAXI"..port.."_AWADDR_RV"):terraReady()]
    self.ready[1] = [mod:getGlobal("IP_MAXI"..port.."_WDATA_RV"):terraReady()]
  end

  return MT.new(WriteBytes)
end

return SOCMT
