local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RM = require "modules"
local types = require "types"
local SDF = require "sdf"
types.export()


-- test underflow block

regs = SOC.axiRegs{}:instantiate()

--[=[
Top = G.Module{types.null(),function(i)
                 local o = regs.start(i)
                 o= G.AXIReadBurstSeq{"frame_128.raw",{128,64},u(8),0}(o)
                 o= G.HS{G.CropSeq{{128,64},{0,0,0,63},0}}(o)
                 o=RM.underflow(u8,128*2,128+8,false,nil,true,0)(o)
                 print("OT",o.type)
                 o=G.AXIWriteBurstSeq{"out/soc_underflow",{128,2},0}(o)
                 return regs.done(o)
               end}

print(Top)
]=]

harness{
  regs.start,
  G.AXIReadBurstSeq{"frame_128.raw",{128,64},u(8),0},
  G.HS{G.CropSeq{{128,64},{0,0,63,0},0}},
  RM.underflow(u8,128*2,128+8,false,nil,true,0,SDF{1,2}),
  G.AXIWriteBurstSeq{"out/soc_underflow",{128,2},0},
  regs.done}
