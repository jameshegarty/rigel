local R = require "rigel"
local MT = require "modulesTerra"
local types = require "types"
local cstdio = terralib.includec("stdio.h")
local cstdlib = terralib.includec("stdlib.h")
local cstring = terralib.includec("string.h")
local J = require "common"

local data = macro(function(i) return `i._0 end)
local valid = macro(function(i) return `i._1 end)

local SOCMT = {}

--SOCMT.doneHack = global(bool)

function SOCMT.axiRegsN(mod,port)
  local struct AxiRegsN { startReg:bool, doneReady:bool, startReady:bool, doneReg:bool, RDATAReady:bool }

  terra AxiRegsN:reset()
    self.startReg = false
    self.doneReg = false
    [mod:getGlobal("IP_SAXI"..port.."_ARADDR"):terraReady()] = true
    [mod:getGlobal("IP_SAXI"..port.."_AWADDR"):terraReady()] = true
    [mod:getGlobal("IP_SAXI"..port.."_WDATA"):terraReady()] = true
--    [SOCMT.doneHack] = false
  end

  terra AxiRegsN:start( out : &bool )
    if valid([mod:getGlobal("IP_SAXI"..port.."_AWADDR"):terraValue()]) then
      --cstdio.printf("WRITE TO REG\n")
      data([mod:getGlobal("IP_SAXI"..port.."_BRESP"):terraValue()]) = 0
      valid([mod:getGlobal("IP_SAXI"..port.."_BRESP"):terraValue()]) = true
      self.startReg = true
      self.doneReg = false
--      [SOCMT.doneHack] = false
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
  end

  return MT.new(AxiRegsN)
end

function SOCMT.axiBurstReadN( mod, totalBytes, port, baseAddress )
  assert(type(baseAddress)=="number")
  assert( totalBytes % 128 == 0)

  --print("AXIBURSTREADN ",totalBytes,port)
  
  local outputType = R.Handshake(types.bits(64))
  --local stride = (R.extractData(outputType):sizeof())
  local struct ReadBurst { nextByteToRead:uint, ready:bool, bytesRead:uint, readyDownstream:bool, addrReadyDownstream:bool }

  --print("SOCMT.readBurst stride:",stride)
  --oassert(stride==8)
  
  terra ReadBurst:reset()
    self.nextByteToRead = totalBytes
    [mod:getGlobal("IP_MAXI"..port.."_RDATA"):terraReady()] = true
    self.ready = true
    self.bytesRead = 0
  end

  terra ReadBurst:process( trigger:&bool, dataOut:&R.lower(outputType):toTerraType() )
    if @trigger and self.nextByteToRead >= totalBytes then
      --cstdio.printf("READ BURST START\n")
      self.nextByteToRead = 0
      self.bytesRead = 0
    end

    if self.nextByteToRead<totalBytes then
      var addr = self.nextByteToRead+[baseAddress]
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
    elseif self.nextByteToRead<totalBytes and [mod:getGlobal("IP_MAXI"..port.."_ARADDR"):terraReady()]==false then
      cstdio.printf("readBurst: want to read, but ARREADY is false\n")
    elseif self.nextByteToRead>=totalBytes then
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
    [mod:getGlobal("IP_MAXI"..port.."_RDATA"):terraReady()] = readyDownstream

    --if readyDownstream==false then
    --  cstdio.printf("AXIBURSTREADN not ready DS\n")
    --end
  
    self.addrReadyDownstream = [mod:getGlobal("IP_MAXI"..port.."_ARADDR"):terraReady()];
    self.readyDownstream = readyDownstream
  end

  return MT.new(ReadBurst)
end


function SOCMT.axiBurstWriteN( mod, Nbytes, port, baseAddress )
  assert(type(baseAddress)=="number")

  --print("AXIBURSTWRITE ",Nbytes,port)
  local struct WriteBurst { nextByteToWrite:uint, ready:bool, addrReadyDownstream:bool, doneReg:bool, writtenBytes:uint, readyDownstream:bool, dataBuffer:uint64, writeFirst:bool }

  local inputType = R.Handshake(types.bits(64))
  --local stride = (R.extractData(inputType):sizeof())
  
  terra WriteBurst:reset()
    self.nextByteToWrite = Nbytes
    self.doneReg = true
    self.writtenBytes = Nbytes
    self.writeFirst = false
  end

  terra WriteBurst:process( dataIn:&R.lower(inputType):toTerraType(), done:&bool )
    if valid(dataIn) and self.nextByteToWrite==Nbytes and self.writtenBytes==Nbytes and self.writeFirst==false then
      -- starting
      cstdio.printf("BurstWrite: start to send addresses %d %d %d\n",self.nextByteToWrite,valid(dataIn),data(dataIn))

      self.nextByteToWrite = 0
      self.dataBuffer = data(dataIn)
      self.doneReg = false
      self.writeFirst = true
      self.writtenBytes = 0
      
      valid([mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraValue()]) = false
    elseif self.writeFirst then
      cstdio.printf("WRITEFIRST %d %d\n",self.nextByteToWrite,[mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraReady()])
      valid([mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraValue()]) = (self.nextByteToWrite>0)
      cstring.memcpy( &data([mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraValue()]), &self.dataBuffer, [R.extractData(inputType):sizeof()] )

      if (self.nextByteToWrite>0) and [mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraReady()] then
        self.writeFirst=false
        self.writtenBytes = self.writtenBytes + 8
      end
    elseif valid(dataIn) and self.nextByteToWrite>0 then
      valid([mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraValue()]) = true

      cstring.memcpy( &data([mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraValue()]), &data(dataIn), [R.extractData(inputType):sizeof()] )

      if self.ready then
        self.writtenBytes = self.writtenBytes + 8

        if self.writtenBytes>self.nextByteToWrite then
          cstdio.printf("WROTE TOO MUCH? writtenBytes:%d  nextByteToWrite:%d totalBytes:%d\n",self.writtenBytes, self.nextByteToWrite,[Nbytes])
          cstdlib.exit(1)
        end
      end
    else
      valid([mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraValue()]) = false
    end

    if self.nextByteToWrite<Nbytes then
      var addr = self.nextByteToWrite+[baseAddress]
      
      valid([mod:getGlobal("IP_MAXI"..port.."_AWADDR"):terraValue()]) = true
      data([mod:getGlobal("IP_MAXI"..port.."_AWADDR"):terraValue()]) = addr

      [mod:getGlobal("IP_MAXI"..port.."_AWLEN"):terraValue()] = 15
      [mod:getGlobal("IP_MAXI"..port.."_AWSIZE"):terraValue()] = 3
      [mod:getGlobal("IP_MAXI"..port.."_AWBURST"):terraValue()] = 1
      [mod:getGlobal("IP_MAXI"..port.."_WSTRB"):terraValue()] = 255

      if self.addrReadyDownstream then
        self.nextByteToWrite = self.nextByteToWrite + 128
      end
    else
      valid([mod:getGlobal("IP_MAXI"..port.."_AWADDR"):terraValue()]) = false
    end

    @done = (self.writtenBytes==Nbytes) and (self.doneReg==false)

--    if @done and self.readyDownstream then
--      cstdio.printf("WriteBurst: DONE\n")
--    end
    
    if (self.writtenBytes==Nbytes) and self.readyDownstream then
      self.doneReg = true
    end
  end

  terra WriteBurst:calculateReady(readyDownstream:bool)
    --cstdio.printf("WRITEBUSRT CALCReADY\n")
    self.ready = [mod:getGlobal("IP_MAXI"..port.."_WDATA"):terraReady()] and (self.writeFirst==false);
    self.addrReadyDownstream = [mod:getGlobal("IP_MAXI"..port.."_AWADDR"):terraReady()];
    self.readyDownstream = readyDownstream
  end

  return MT.new(WriteBurst)
end

function SOCMT.axiReadBytes( mod, Nbytes, port, addressBase )
  assert(type(addressBase)=="number")

  --print("AXIBURSTREADN ",totalBytes,port)

  local inputType = R.Handshake(types.uint(32))
  local outputType = R.Handshake(types.bits(64))

  local struct ReadBytes { ready:bool }

  local burstCount = Nbytes/8
  J.err( burstCount<=16,"axiReadBytes: NYI - burst longer than 16")

  terra ReadBytes:reset()
    [mod:getGlobal("IP_MAXI"..port.."_RDATA"):terraReady()] = false
    self.ready = true
  end

  terra ReadBytes:process( dataIn:&R.lower(inputType):toTerraType(), dataOut:&R.lower(outputType):toTerraType() )

  if valid(dataIn) then

    var addr = data(dataIn)+[addressBase]
    --cstdio.printf("READ REQ %d, %d\n", data(dataIn),[addressBase])
      --cstdio.printf("readBurst: send address %d port %d ready %d\n",self.nextByteToRead, port, [mod:getGlobal("IP_MAXI"..port.."_ARADDR"):terraReady()])
      valid([mod:getGlobal("IP_MAXI"..port.."_ARADDR"):terraValue()]) = true
      data([mod:getGlobal("IP_MAXI"..port.."_ARADDR"):terraValue()]) = addr
      [mod:getGlobal("IP_MAXI"..port.."_ARLEN"):terraValue()] = [burstCount-1]
      [mod:getGlobal("IP_MAXI"..port.."_ARSIZE"):terraValue()] = 3
      [mod:getGlobal("IP_MAXI"..port.."_ARBURST"):terraValue()] = 1

    elseif valid(dataIn) and [mod:getGlobal("IP_MAXI"..port.."_ARADDR"):terraReady()] then
      cstdio.printf("readBytes: want to read, but ARREADY is false\n")
    else
      valid([mod:getGlobal("IP_MAXI"..port.."_ARADDR"):terraValue()]) = false
    end

    if valid([mod:getGlobal("IP_MAXI"..port.."_RDATA"):terraValue()]) then
      cstring.memcpy( &data(dataOut), &data([mod:getGlobal("IP_MAXI"..port.."_RDATA"):terraValue()]), [R.extractData(outputType):sizeof()] )
      valid(dataOut) = true
      --cstdio.printf("READDAT %d R %d\n",data(dataOut),[mod:getGlobal("IP_MAXI"..port.."_RDATA"):terraReady()])
    else
      valid(dataOut) = false
      --cstdio.printf("READDAT IV %d\n",data(dataOut))
    end
  end

  terra ReadBytes:calculateReady(readyDownstream:bool)
    --cstdio.printf("READBUSRT CALCReADY\n")
    [mod:getGlobal("IP_MAXI"..port.."_RDATA"):terraReady()] = readyDownstream
    self.ready = [mod:getGlobal("IP_MAXI"..port.."_ARADDR"):terraReady()]
  end

  return MT.new(ReadBytes)
end

return SOCMT
