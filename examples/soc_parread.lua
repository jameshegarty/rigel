local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
local types = require "types"
local RM = require "modules"
local SDF = require "sdf"
types.export()
local Zynq = require "zynq"

local regs = SOC.axiRegs({},SDF{1,(128*64)/16}):instantiate("regs")

local noc = Zynq.SimpleNOC(2,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

-- this will use 2 AXI ports to read in parallel at twice the BW

local Top = G.Module{"Top",types.null(),
  function(inp)
    local out = regs.start(inp)
    out = C.AXIReadPar("frame_128.raw",128,64,types.uint(8),16,noc)(out)
    print("RP",out.rate)
    out = G.HS{RM.downsampleXSeq(types.uint(8),128,64,16,2)}(out)
    out = G.AXIWriteBurstSeq{"out/soc_parread",{64,64},8,noc.write}(out)
    return regs.done(out)
  end,{regs}}

harness(Top)
