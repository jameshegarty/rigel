local R = require "rigel"
local G = require "generators.core"
local harness = require "generators.harnessSOC"
local SOC = require "generators.soc"
local SDF = require "sdf"
local types = require "types"
local Zynq = require "generators.zynq"

local cycles = tonumber(string.match(arg[0],"%d+"))

local regs = SOC.axiRegs({},SDF{1,cycles}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local Conv = G.Module{ "ConvTop", SDF{1,cycles},
  function(i)
    local p = G.AXIReadBurst{"frame_128.raw",{128,64},types.u8,noc.read}(i)
--    print("READBURST",p)
    local s = G.Stencil{{-3,0,-3,0}}(p)
--    print("STENCIL",s,s.type)
    s = G.Reshape(s)
    print("RESHAPE",s.type)
    s = G.Reshape(s)
    print("RESHAPE",s.type)
    
--    s = G.Reshape(s)
--    print("RESHAPE",s.type)
    --print("REhhhSHAPE",s)
    --local f = G.HS{G.Map{G.Map{G.Rshift{4}}}}(s)
    local f = G.Rshift{4}(s)
--    print("FTYPE",f.type)
    local o = G.Reduce{G.Add{R.Async}}(f)
--    print("REDTYPE",o.type)
    o = G.Crop{{24,0,3,0}}(o)
    return G.AXIWriteBurst{"out/soc_redu"..tostring(cycles),noc.write}(o)
  end}

print("CONVTOP")
print(Conv{R.HandshakeTrigger})

harness({regs.start,Conv,regs.done},nil,{regs})
