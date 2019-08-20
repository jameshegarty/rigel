local R = require "rigel"
local SOC = require "generators.soc"
local C = require "generators.examplescommon"
local harness = require "generators.harnessSOC"
local G = require "generators.core"
local RM = require "generators.modules"
local types = require "types"
local SDF = require "sdf"
types.export()
local Zynq = require "generators.zynq"

-- test underflow block
local regs = SOC.axiRegs({},SDF{1,128*64}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

harness({
  regs.start,
  G.AXIReadBurstSeq{"frame_128.raw",{128,64},u(8),0,noc.read},
  G.Map{G.CropSeq{{128,64},{0,0,63,0},0,types.rv(types.Par(u8)),SDF{1,1}}},
  RM.underflow(u8,128*2,128+8,false,nil,true,0,SDF{1,2}),
  G.AXIWriteBurstSeq{"out/soc_underflow",{128,2},0,noc.write},
  regs.done},nil,{regs})
