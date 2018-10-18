local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RS = require "rigelSimple"
local RM = require "modules"
local SDF = require "sdf"
local types = require "types"
local J = require "common"
types.export()

--local Regs = SOC.axiRegs{count={u8,0,"out"}}
local Regs = SOC.axiRegs{}
regs = Regs:instantiate()

--BoolGT = G.Module{"BoolGT",function(i) return G.Not(G.And(G.Not(i[0][1]),i[1][1])) end}
IdxGT = G.Module{"IdxGT",function(i) return G.GT(i[0][1],i[1][1]) end}

-- input type: {{A,bool},u8} -> {A,u8}
BoolToIdxInner = G.Module{"BoolToIdxInner", function(i) return R.concat{i[0][0],G.Sel(i[0][1],i[1],R.c(0,u8))} end}

BoolToIdx = G.Module{"BoolToIdx",SDF{1,1},
                     function(i)
                       print("BIX",i.type)
                       local tmp = R.c(J.reverse(J.range(1,8)),types.array2d(u8,8))
                       tmp = G.Zip(i,tmp)
                       print("TMP",tmp.type)
                       return G.Map{BoolToIdxInner}(tmp)
                     end}

-- {A,u8}->{A,bool} (if u8>0)
IdxToBool = G.Module{"IdxToBool", function(i) return R.concat{i[0],G.GT{0}(i[1])} end }

OffsetModule = G.Module{ "OffsetModule", R.HandshakeTrigger,
  function(i)
    local readStream = G.AXIReadBurstSeq{"frame_128.raw",{128,64},u(8),8}(i)
    --    print(readStream.fn)
    print("READSTRAM",readStream.rate)
    local rs = G.FanOut{2}(readStream)
    local rs0 = G.FIFO{128}(rs[0])
    local rs1 = G.FIFO{128}(rs[1])
    local filt = G.HS{G.Map{G.GT{192}}}(rs1)
    print("FILTa",filt.type)

    print("FILT",filt.type)
    local finp = G.FanIn(rs0,filt)
    print("FINP",finp.type)
    finp = G.HS{G.Zip}(finp)
    print("FINP",finp.type)
    finp = G.HS{BoolToIdx}(finp)
    print("BOOLTOIDX",finp.type)
    finp = G.HS{G.Sort{IdxGT}}(finp)
    finp = G.HS{G.Map{IdxToBool}}(finp)
    print("IDXTOBOOL",finp.type)
    
    -- 368
    local offset = G.HS{RM.filterSeqPar(u8,8,SDF{368,8192})}(finp)
    print("OFFSET",offset.type,offset,offset.rate)
    offset = G.HS{G.Broadcast{1}}(offset)
    offset = G.HS{G.Deser{8}}(offset)
    
    
    local res = G.AXIWriteBurstSeq{"out/soc_filterseq8",{368,1},8}(offset)
    print("RES",res.rate)
--    print(res.fn)
    return res
  end}

harness{regs.start, OffsetModule, regs.done}
