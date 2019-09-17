local R = require "rigel"
local SOC = require "generators.soc"
local C = require "generators.examplescommon"
local harness = require "generators.harnessSOC"
local G = require "generators.core"
local RS = require "rigelSimple"
local RM = require "generators.modules"
local SDF = require "sdf"
local types = require "types"
local J = require "common"
types.export()
local Zynq = require "generators.zynq"

local regs = SOC.axiRegs({},SDF{1,1024}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

-- The basic idea of this sort is:
-- we take an array of V {A,bool} pairs (A vectorized sparse array)
-- Assign a index to each pair, where higher indices in the array get higher indexes
--    false bool values get a 0 index.
-- Then: sort, and throw out the indexes and convert back to bools.
-- We need to do the index thing, b/c we want to keep items in order.

-- input {{A,u8},{A,u8}}, where the u8 is the index. 
IdxGT = G.Module{"IdxGT",function(i) return G.GT(i[0][1],i[1][1]) end}

-- input type: {{A,bool},u8} -> {A,u8}
-- if bool is true-> return the idx, Else, return 0
BoolToIdxInner = G.Module{"BoolToIdxInner", types.rv(types.Par(types.tuple{types.tuple{u8,types.bool()},u8})),
                          function(i) return R.concat{i[0][0],G.Sel(i[0][1],i[1],R.c(0,u8))} end}

BoolToIdx = G.Module{"BoolToIdx",SDF{1,1},types.rv(types.Par(types.array2d(types.tuple{u8,types.bool()},8))),
                     function(i)
                       print("BIX",i.type)
                       local tmp = R.c(J.reverse(J.range(1,8)),types.array2d(u8,8))
                       tmp = G.Zip(i,tmp)
                       print("TMP",tmp.type)
                       return G.Map{BoolToIdxInner}(tmp)
                     end}

-- {A,u8}->{A,bool} (if u8>0)
IdxToBool = G.Module{"IdxToBool", types.rv(types.Par(types.tuple{u8,u8})),
                     function(i) return R.concat{i[0],G.GT{0}(i[1])} end }

OffsetModule = G.Module{ "OffsetModule", R.HandshakeTrigger,
  function(i)
    local readStream = G.AXIReadBurstSeq{"frame_128.raw",{128,64},u(8),8,noc.read}(i)
    --    print(readStream.fn)
    print("READSTRAM",readStream.rate)
    local rs = G.FanOut{2}(readStream)
    local rs0 = G.FIFO{128}(rs[0])
    local rs1 = G.FIFO{128}(rs[1])
    local filt = G.GT{192}(rs1)
    print("FILTa",filt.type)

    print("FILT",filt.type)
    local finp = G.FanIn(rs0,filt)
    print("FINP",finp.type)
    finp = G.Zip(finp)
    print("FINP",finp.type)
    finp = G.Map{BoolToIdx}(finp)
    print("BOOLTOIDX",finp.type)
    finp = G.Sort{IdxGT}(finp)
    finp = G.Map{IdxToBool}(finp)
    print("IDXTOBOOL",finp.type)
    
    -- 368
    local offset = G.Map{RM.filterSeqPar(u8,8,SDF{368,8192})}(finp)
    print("OFFSET",offset.type,offset,offset.rate)
    --offset = G.Broadcast{1}(offset) -- deleted 8/19
    --offset = G.DeserSeq{8}(offset)
    offset = G.Map{RM.changeRate(u8,1,0,8)}(offset)
    
    local res = G.AXIWriteBurstSeq{"out/soc_filterseq8",{368,1},8,noc.write}(offset)
    print("RES",res.rate)
--    print(res.fn)
    return res
  end}

harness({regs.start, OffsetModule, regs.done},nil,{regs})
