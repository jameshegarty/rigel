local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
local types = require "types"
local SDF = require "sdf"
local Zynq = require "zynq"
types.export()

local regs = SOC.axiRegs({readAddress={u(32),0x30008000},writeAddress={u(32),0x30008000+(128*64)}},SDF{1,128*64}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

OffsetModule = G.Module{ "OffsetModule", R.HandshakeTrigger,
  function(i)
    local readStream = SOC.axiBurstReadN("frame_128.raw",128*64,regs.readAddress,noc.read)(i)
    readStream = G.HS{C.bitcast(b(64),ar(u(8),8))}(readStream)
    local offset = G.HS{G.Map{G.Add{200}}}(readStream)
    offset = G.HS{C.bitcast(ar(u(8),8),b(64))}(offset)
    return SOC.axiBurstWriteN("out/soc_simple_uniform",128*64,regs.writeAddress,noc.write)(offset)
  end}

-- tell the system how much memory we want
SOC.currentAddr = 0x3000c000
print(OffsetModule)
OffsetModule.globalMetadata["InstCall_ZynqNOC_write_write_W"]=128
OffsetModule.globalMetadata["InstCall_ZynqNOC_write_write_H"]=64

harness({regs.start, OffsetModule, regs.done},nil,{regs})
