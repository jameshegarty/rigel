local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
local types = require "types"
local SDF = require "sdf"
types.export()

local Regs = SOC.axiRegs({offset={u(8),200},lastPx={u(8),0,"input"}},SDF{1,8192})
regs = Regs:instantiate()

local AddReg = G.Module{"AddReg",function(i) return G.Add(i,Regs.offset) end}

local RegInOut = G.Module{
  function(i)
    local inputStream = G.AXIReadBurst{"frame_128.raw",{128,64},u(8),0}(i)
    local pipeOut = G.HS{G.Map{AddReg}}(inputStream)
    pipeOut = G.FanOut{2}(pipeOut)
    local doneFlag = G.AXIWriteBurst{"out/soc_regout"}(pipeOut[0])
    local writeRegStatement = G.Map{G.WriteGlobal{Regs.lastPx}}(pipeOut[1])
    return R.statements{doneFlag,writeRegStatement}
  end}

harness{regs.start,RegInOut,regs.done}
