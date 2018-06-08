local R = require "rigel"
local MT = require "modulesTerra"
local types = require "types"
local cstdio = terralib.includec("stdio.h")
local cstdlib = terralib.includec("stdlib.h")

local data = macro(function(i) return `i._0 end)
local valid = macro(function(i) return `i._1 end)

local SOCMT = {}

function SOCMT.axiRegsN(mod,port)
  local struct AxiRegsN { readyReg:bool }

  terra AxiRegsN:reset()
    self.readyReg = false
    [mod:getGlobal("IP_SAXI"..port.."_ARADDR"):terraReady()] = true
    [mod:getGlobal("IP_SAXI"..port.."_AWADDR"):terraReady()] = true
  end

  terra AxiRegsN:start( out : &bool )
    if valid([mod:getGlobal("IP_SAXI"..port.."_AWADDR"):terraValue()]) then
      cstdio.printf("WRITE TO REG\n")
    end
  end

  terra AxiRegsN:done( inp : &bool )

  end

  return MT.new(AxiRegsN)
end

function SOCMT.readBurst( mod, port, totalBytes, outputType )
  assert( types.isType(outputType) )
  
  local struct ReadBurst { nextByteToRead:uint}

  terra ReadBurst:reset()
    self.nextByteToRead = totalBytes+1
  end

  terra ReadBurst:process( trigger:&bool, dataOut:&R.lower(outputType):toTerraType() )
  end

  return MT.new(ReadBurst)
end


function SOCMT.writeBurst( mod, port, totalBytes, inputType )
  assert( types.isType(inputType) )
  local struct WriteBurst { nextByteToWrite:uint }

  terra WriteBurst:reset()
    self.nextByteToWrite = totalBytes+1
  end

  terra WriteBurst:process( dataIn:&R.lower(inputType):toTerraType(), done:&bool )
  end

  return MT.new(WriteBurst)
end

return SOCMT
