local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
local types = require "types"
types.export()

Regs = SOC.axiRegs{readAddress={u(32),0x30008000},writeAddress={u(32),0x30008000+(128*64)}}
regs = Regs:instantiate()

OffsetModule = G.Module{ "OffsetModule", R.HandshakeTrigger,
  function(i)
    local readStream = SOC.axiBurstReadN("frame_128.raw",128*64,0,Regs.readAddress.global)(i)
    readStream = G.HS{C.bitcast(b(64),ar(u(8),8))}(readStream)
    local offset = G.HS{G.Map{G.Add{200}}}(readStream)
    offset = G.HS{C.bitcast(ar(u(8),8),b(64))}(offset)
    return SOC.axiBurstWriteN("out/soc_simple_uniform",128*64,0,Regs.writeAddress.global)(offset)
  end}

--print(OffsetModule)
--print(OffsetModule:toVerilog())

-- tell the system how much memory we want
SOC.currentAddr = 0x3000c000
print(OffsetModule)
OffsetModule.globalMetadata["MAXI0_write_W"]=128
OffsetModule.globalMetadata["MAXI0_write_H"]=64

harness{regs.start, OffsetModule, regs.done}
