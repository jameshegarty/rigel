local R = require "rigel"
local SOC = require "generators.soc"
local C = require "generators.examplescommon"
local harness = require "generators.harnessSOC"
local G = require "generators.core"
local RS = require "rigelSimple"
local types = require "types"
local SDF = require "sdf"
local Zynq = require "generators.zynq"
local RM = require "generators.modules"
local Uniform = require "uniform"
types.export()

local regs = SOC.axiRegs({{"readAddress",RM.reg(u(32),0x30008000)},{"writeAddress",RM.reg(u(32),0x30008000+(128*64))}},SDF{1,128*64}):instantiate("regs")

local readAddress = Uniform(regs.readAddress)
readAddress:addProperty(readAddress:ge(0x30008000))
readAddress:addProperty(readAddress:le(0x30008000))

local writeAddress = Uniform(regs.writeAddress)
writeAddress:addProperty(writeAddress:ge(0x30008000+(128*64)))
writeAddress:addProperty(writeAddress:le(0x30008000+(128*64)))

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

OffsetModule = G.Function{ "OffsetModule", R.HandshakeTrigger,
  function(i)
    local readStream = SOC.readBurst("frame_128.raw",128,64,u8,8,true,readAddress,noc.read)(i)
    local offset = G.Map{G.Add{200}}(readStream)
    return SOC.writeBurst("out/soc_simple_uniform",128,64,u8,8,1,true,noc.write,writeAddress)(offset)
  end}

-- tell the system how much memory we want
SOC.currentAddr = 0x3000c000

OffsetModule.globalMetadata["InstCall_ZynqNOC_write_write_W"]=128
OffsetModule.globalMetadata["InstCall_ZynqNOC_write_write_H"]=64

harness({regs.start, OffsetModule, regs.done},nil,{regs})
