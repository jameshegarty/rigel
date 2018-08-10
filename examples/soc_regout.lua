local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
require "types".export()

local Regs = SOC.axiRegs{offset={u(32),200},lastPx={u(8),0,"out"}}
regs = Regs:instantiate()

print("REGS",Regs.offset)

local AddReg = G.Module{"AddReg",function(i) return G.Add(i,G.RemoveMSBs{24}(Regs.offset)) end}

local Top = G.Module{"Top",
  function(i)
    local o = regs.start(i)
    o = SOC.readBurst("frame_128.raw",128,64,u(8),0)(o)
    local pipeOut = G.HS{AddReg}(o)
    pipeOut = G.FanOut{2}(pipeOut)
    local pipeOut0 = R.selectStream("ob0",pipeOut,0)
    local pipeOut1 = R.selectStream("ob1",pipeOut,1)
    o = SOC.writeBurst("out/soc_regout",128,64,u(8),0)(pipeOut0)
    o = regs.done(o)
    return R.statements{o,R.writeGlobal("go",Regs.lastPx,pipeOut1)}
  end}

harness(Top)
