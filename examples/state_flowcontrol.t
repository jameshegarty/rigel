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
  fifo : RM.fifo(AXI.ReadDataTuple(64),8,nil,nil,nil,nil,nil,true,nil,true)
  addrsInFlight : u8 = 0
--1
  while R.c(true,types.bool()) do
    if G.LT(addrsInFlight,8) then
      [fifo:store(noc.read(I))]
      --      if G.And(noc.read.ready, Valid(I)) then
      if XFR(noc.read,I) then
        addrsInFlight = G.Add(addrsInFlight,R.c(1,u8))
      end
    else
      [C.Stall(AXI.ReadAddressTuple,true)(I)]
      [fifo:store(noc:read(C.Invalid(AXI.ReadAddressTuple,true)()))]
    end
    --if G.And(O.ready,valid(fifo.load())) then
    if XFR(O,fifo.load) then
      addrsInFlight = addrsInFlight-1
    end
    yield fifo:load() -- 2
  end
end

--l-ocal FC = FlowControl(noc.read)
--print(FlowControl)
--print(FlowControl:toVerilog())


harness({regs.start, G.AXIReadBurst{ "frame_128.raw", {128,64}, types.u(8), 0, FlowControl }, G.HS{G.Map{G.Add{200}}}, G.AXIWriteBurst{"out/state_flowcontrol",noc.write}, regs.done},nil,{regs})
