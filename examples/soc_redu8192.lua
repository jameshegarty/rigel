local R = require "rigel"
local G = require "generators"
local harness = require "harnessSOC"
local SOC = require "soc"
local SDF = require "sdf"
local types = require "types"
local Zynq = require "zynq"

local cycles = tonumber(string.match(arg[0],"%d+"))

noc = Zynq.SimpleNOC():instantiate("ZynqNOC")
noc.extern=true
local regs = SOC.axiRegs({},SDF{1,cycles},noc.readSource,noc.readSink,noc.writeSource,noc.writeSink):instantiate("regs")

local Conv = G.Module{ "ConvTop", SDF{1,cycles},
  function(i)
    local p = G.AXIReadBurst{"frame_128.raw",{128,64},types.u8,noc.read}(i)
    local s = G.HS{G.Stencil{{3,0,3,0}}}(p)
    s = G.Reshape(s)
    local f = G.HS{G.Map{G.Map{G.Rshift{4}}}}(s)
    print("FTYPE",f.type)
    local o = G.HS{G.Map{G.Reduce{G.Add{true}}}}(f)
    o = G.HS{G.Crop{{24,0,3,0}}}(o)
    return G.AXIWriteBurst{"out/soc_redu"..tostring(cycles),noc.write}(o)
  end}

print("CONVTOP")
print(Conv{R.HandshakeTrigger})

harness({regs.start,Conv,regs.done},nil,{regs})
