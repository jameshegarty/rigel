local types = require "types"
local C = require "examplescommon"
local R = require "rigel"
local harness = require "harnessSOC"
local Zynq = require "zynq"
local SOC = require "soc"
local SDF = require "sdf"
local G = require "generators"
import "state"

state StateExample(I:types.uint(8),O:types.uint(8))
--1
  while R.c("mytrue",true,types.bool()) do
    if C.GTConst(types.uint(8),16)(I) then
      yield R.c(255,types.u8) --2

      if C.GTConst(types.uint(8),128)(I) then
        yield R.c(128,types.u8) --3
      else
        yield R.c(64,types.u8) --4 
      end
    else
      yield R.c(0,types.u8) --5
    end
  end
end

print("COUNTER",StateExample)

print("counter",StateExample:toVerilog())

noc = Zynq.SimpleNOC():instantiate("ZynqNOC")
noc.extern=true
local regs = SOC.axiRegs({},SDF{1,128*64},noc.readSource,noc.readSink,noc.writeSource,noc.writeSink):instantiate("regs")

harness({regs.start, G.AXIReadBurst{ "frame_128.raw", {128,64}, types.u(8), 0, noc.read }, G.Map{G.HS{StateExample}}, G.AXIWriteBurst{"out/stateex",noc.write}, regs.done},nil,{regs})
