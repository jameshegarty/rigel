local R = require "rigel"
local SOC = require "soc"
local C = require "examplescommon"
local harness = require "harnessSOC"
local G = require "generators"
local RM = require "modules"
local types = require "types"
types.export()
local SDF = require "sdf"
local Zynq = require "zynq"

local bjump = require "bjump"

-- this does a wide (128 bit) read per pixel, which can't be serviced in a single AXI bus request.
-- So, without cache this should take approx (1920*1080*2)/8 cycles
-- But, with cache should take (1920*1080)/8 cycles

local W,H = 1920/8,1024/8
noc = Zynq.SimpleNOC():instantiate("ZynqNOC")
noc.extern=true
local regs = SOC.axiRegs({},SDF{1,W*H},noc.readSource,noc.readSink,noc.writeSource,noc.writeSink):instantiate("regs")

local PosToAddr = G.Module{"PosToAddr",ar(u16,2),
  function(loc)
    return C.cast(u16,u32)(G.Add(G.Mul(loc[1],R.constant(1920,u16)),loc[0]))
  end}

local SlowRead = C.compose("SlowRead",SOC.read("frame_128.raw",128*64,ar(u8,4),noc.read),RM.liftHandshake(RM.reduceThroughput(types.uint(32),8)))

local CachedReadModule = G.Module{ "CachedReadModule", R.HandshakeTrigger,
  function(i)
    i = G.TriggerBroadcast{W*H}(i)
    local pos = G.HS{G.Pos{{W,H},0}}(i)
    local posScaled = G.HS{G.Map{G.Map{G.Mul{8}}}}(pos) -- mult coords by 8
    posScaled = G.HS{G.Map{PosToAddr}}(posScaled) -- mult coords by 8
    local stencil = G.Map{bjump.AXICachedRead(ar(u(8),4),16,8,SlowRead)}(posScaled)
    local shifted = G.HS{G.Map{G.Map{G.Rshift{3}}}}(stencil)
    local fin = G.HS{G.Map{G.Reduce{G.Add}}}(shifted)
    return G.AXIWriteBurst{"out/soc_bjump_cache",noc.write}(fin)
  end}

print(CachedReadModule)

harness({regs.start, CachedReadModule, regs.done},nil,{regs})
