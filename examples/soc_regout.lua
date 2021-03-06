local R = require "rigel"
local SOC = require "generators.soc"
local C = require "generators.examplescommon"
local harness = require "generators.harnessSOC"
local G = require "generators.core"
local RM = require "generators.modules"
local RS = require "rigelSimple"
local types = require "types"
local SDF = require "sdf"
local T = require "types"
types.export()

local Zynq = require "generators.zynq"

local regs = SOC.axiRegs({{"offset",RM.reg(u(8),200)},{"lastPx",RM.reg(u(8),0,true)}},SDF{1,8192}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local AddReg = G.Function{ "AddReg", types.rv(types.Par(u8)), SDF{1,1}, function(i) return G.Add(i,RM.Storv(regs.offset)(G.ValueToTrigger(i))) end }

local RegInOut = G.Function{ "RegInOut", types.HandshakeTrigger, SDF{1,8192},
  function(i)
    local inputStream = G.AXIReadBurst{"frame_128.raw",{128,64},u(8),0,noc.read}(i)
    local pipeOut = G.Map{AddReg}(inputStream)
    pipeOut = G.FanOut{2}(pipeOut)
    local doneFlag = G.AXIWriteBurst{"out/soc_regout",noc.write}(pipeOut[0])
    local writeRegStatement = G.Map{regs.lastPx}(pipeOut[1])
    return R.statements{doneFlag,writeRegStatement}
  end}

harness({regs.start,RegInOut,regs.done},nil,{regs})
