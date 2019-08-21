local R = require "rigel"
local SOC = require "generators.soc"
local C = require "generators.examplescommon"
local harness = require "generators.harnessSOC"
local G = require "generators.core"
local RM = require "generators.modules"
local J = require "common"
local types = require "types"
types.export()
local SDF = require "sdf"
local Zynq = require "generators.zynq"

local bjump = require "generators.bjump"

-- bjump cache must load 32bit chunks
-- this does a blur in X. we load 32 pixels in X and sum them. We decimate by 4x in X (read every 4 px), 8x in Y.
-- axi bus is artificially slowed by 8x. If cache works, we expect runtime to be approx 128*64*8. If uncached, it should be 128*64*8*8

local NOCACHE = string.find(arg[0],"nocache")

local W,H = 128,64
local regs = SOC.axiRegs({},SDF{1,W*H*8*8}):instantiate("regs")

noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true


local PosToAddr = G.Module{"PosToAddr",
                           --types.rv(types.Par(ar(u16,2))),
                           types.rv(types.Par(types.tuple{u16,u16})),
  function(loc)
    local i = G.PosSeq{{8,1},0}() -- inner loop from 0...2
    local x = G.Mul(G.Add(loc[0],i[0]),R.constant(4,u16)) -- (x+i.x)*4
    return C.cast(u16,u32)(G.Add(G.Mul(loc[1],R.constant(1920*8,u16)),x))
  end}

local SlowRead = C.compose("SlowRead",SOC.read("1080p.raw",1920*1080,ar(u8,4),noc.read,false),RM.liftHandshake(RM.reduceThroughput(types.uint(32),8)))
local SlowReadBurst = C.compose("SlowReadBurst",SOC.read("1080p.raw",1920*1080,ar(u8,4*8),noc.read,false),RM.liftHandshake(RM.reduceThroughput(types.uint(32),8)))
local SlowBurstReadSer = C.compose("SlowBurstReadSer",G.SerSeq{8},SlowReadBurst)

local CachedReadModule = G.Module{ "CachedReadModule", R.HandshakeTrigger,
  function(i)
    i = G.TriggerBroadcast{W*H}(i)
    local pos = G.PosSeq{{W,H},0}(i)

    local posDup = G.Broadcast{{8,1}}(pos)
    local addr = G.Map{PosToAddr}(posDup) -- mult coords by 8

    local stencil
    if NOCACHE then
      stencil = G.Map{SlowRead}(addr)
    else
      stencil = G.Map{bjump.AXICachedRead(ar(u(8),4),8,8,SlowBurstReadSer)}(addr)
    end
    
    stencil = G.Deser{8}(stencil)

    local shifted = G.Rshift{5}(stencil)
    local fin = G.Reduce{G.Add{R.Async}}(shifted)
    return G.AXIWriteBurstSeq{"out/soc_bjump_cache"..J.sel(NOCACHE,"_nocache",""),noc.write,8,{W,H}}(fin)
  end}

print(CachedReadModule)

harness({regs.start, CachedReadModule, regs.done},nil,{regs})
