local R = require "rigel"
local RM = require "modules"
local S = require "systolic"
local types = require "types"
local J = require "common"
local SOC = {}

local PORTS = 4

SOC.frameStart = R.newGlobal("frameStart","input", R.Handshake(types.null()),{nil,false})

SOC.readAddrs = J.map(J.range(PORTS),function(i) return R.newGlobal("readAddr"..tostring(i),"output",R.Handshake(types.uint(32)),{0,false}) end)

SOC.readData = J.map(J.range(PORTS),function(i) return R.newGlobal("readData"..tostring(i),"input",R.Handshake(types.bits(64))) end)

SOC.writeAddrs = J.map(J.range(PORTS),function(i) return R.newGlobal("writeAddr"..tostring(i),"output",R.Handshake(types.uint(32)),{0,false}) end)
SOC.writeData = J.map(J.range(PORTS),function(i) return R.newGlobal("writeData"..tostring(i),"output",R.Handshake(types.bits(64)),{0,false}) end)
  
-- does a 128 byte burst
-- uint25 addr -> bits(64)
SOC.bulkRamRead = J.memoize(function(port)
  err( type(port)=="number", "bulkRamRead: port must be number" )
  err( port>0 and port<=PORTS,"bulkRamRead: port out of range" )
      
  local H = require "rigelhll"
  local brri = R.input(R.Handshake(types.uint(25)))
  local addr = H.liftSystolic(function(i) return S.lshift(S.cast(i,H.u32),S.constant(7,H.u8)) end)(brri)
  --brri = H.cast(H.u32)(brri)
  --brri = H.lshift(brri,H.c(H.u8,7))

  local pipelines = R.statements{ R.readGlobal( "ramread", SOC.readData[port] ), R.writeGlobal( "addrwrite", SOC.readAddrs[port], addr ) }

  return RM.lambda("bulkRamRead_"..tostring(port),brri,pipelines)
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
