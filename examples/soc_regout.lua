local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
local types = require "types"
local SDF = require "sdf"
types.export()

local Zynq = require "zynq"

noc = Zynq.SimpleNOC():instantiate("ZynqNOC")
noc.extern=true
local Regs = SOC.axiRegs({offset={u(8),200},lastPx={u(8),0,"input"}},SDF{1,8192},noc.readSource,noc.readSink,noc.writeSource,noc.writeSink)
local regs = Regs:instantiate("regs")

local AddReg = G.Module{"AddReg",function(i) return G.Add(i,regs.offset()) end}

local RegInOut = G.Module{types.HandshakeTrigger,SDF{1,8192},
  function(i)
    local inputStream = G.AXIReadBurst{"frame_128.raw",{128,64},u(8),0,noc.read}(i)
    local pipeOut = G.HS{G.Map{AddReg}}(inputStream)
    pipeOut = G.FanOut{2}(pipeOut)
    local doneFlag = G.AXIWriteBurst{"out/soc_regout",noc.write}(pipeOut[0])
    local writeRegStatement = G.Map{regs.lastPx}(pipeOut[1])
    print("WRITEREG",writeRegStatement.fn)
    return R.statements{doneFlag,writeRegStatement}
  end}

print("REGINOUT",RegInOut)
print("Regs",Regs)
harness({regs.start,RegInOut,regs.done},nil,{regs})
