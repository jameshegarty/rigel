local types = require "types"
local C = require "examplescommon"
local R = require "rigel"
local harness = require "harnessSOC"
local Zynq = require "zynq"
local SOC = require "soc"
local SDF = require "sdf"
local G = require "generators"
local RM = require "modules"
local AXI = require "axi"
import "state"


--function FlowControl(readFn)
--  return 
--end

noc = Zynq.SimpleNOC():instantiate("ZynqNOC")
noc.extern=true
local regs = SOC.axiRegs({},SDF{1,128*64},noc.readSource,noc.readSink,noc.writeSource,noc.writeSink):instantiate("regs")

print("INST",noc.read)

-- only issue requests for which we have pre-allocated storage
state FlowControl(I:AXI.ReadAddress64,O:AXI.ReadData64)
  fifo:RM.fifo(AXI.ReadDataTuple(64),8,nil,nil,nil,nil,nil,true,nil,true)
--1
  while R.c(true,types.bool()) do
    if G.LT{7}(fifo:size()) then
      [fifo:store(noc.read(I))]
    else
      [C.Stall(AXI.ReadAddressTuple,true)(I)]
      [fifo:store(noc:read(C.Invalid(AXI.ReadAddressTuple,true)()))]
    end
    yield fifo:load() -- 2
  end
end

--l-ocal FC = FlowControl(noc.read)
--print(FlowControl)
--print(FlowControl:toVerilog())


harness({regs.start, G.AXIReadBurst{ "frame_128.raw", {128,64}, types.u(8), 0, FlowControl }, G.HS{G.Map{G.Add{200}}}, G.AXIWriteBurst{"out/state_flowcontrol",noc.write}, regs.done},nil,{regs})
