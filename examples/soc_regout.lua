local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
local types = require "types"
types.export()

local Regs = SOC.axiRegs{offset={u(32),200},lastPx={u(8),0,"out"}}
regs = Regs:instantiate()

local AddReg = G.Module{"AddReg",function(i) return G.Add(i,G.RemoveMSBs{24}(Regs.offset)) end}
local WG = G.Module{"WG",function(i) return R.writeGlobal("go",Regs.lastPx,i) end}

--local WGG = WG{types.Handshake(types.uint(8))}
--print(WGG)
--print(WGG.systolicModule)

local RegOut = G.Module{
  function(i)
    local o = G.AXIReadBurst{"frame_128.raw",{128,64},u(8),0}(i)
    local pipeOut = G.HS{G.Map{AddReg}}(o)
    pipeOut = G.FanOut{2}(pipeOut)
    local doneFlag = G.AXIWriteBurst{"out/soc_regout"}(pipeOut[0])
    return R.statements{doneFlag,G.Map{WG}(pipeOut[1])}
  end}

harness{regs.start,RegOut,regs.done}
