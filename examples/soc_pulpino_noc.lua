local R = require "rigel"
local Pulpino = require "pulpino"
local J = require "common"
local Zynq = require "zynq"
local SOC = require "soc"
local SDF = require "sdf"
local C = require "examplescommon"
local G = require "generators"
local types = require "types"
local harness = require "harnessSOC"

zynqNOC = Zynq.SimpleNOC():instantiate("ZynqNOC")
zynqNOC.extern=true

local noc = Pulpino.AXIInterconnect(3,2):instantiate("pulpinoNOC")
local regs = SOC.axiRegs( {}, SDF{1,(128*64)/8}, noc.readSource1, noc.readSink1, noc.writeSource1, noc.writeSink1 ):instantiate("regs")

local IP_plus200 = C.linearPipeline({G.AXIReadBurst{ "frame_128.raw", {128,32}, types.u8, 8, noc.read1, SDF{1,(128*32)/8} },G.HS{G.Map{G.Add{200}}},G.AXIWriteBurst{"out/soc_simple",noc.write1}},"IP_plus100")

local Inv = G.Module{"Inv",types.u(8),SDF{1,1},function(i) return G.Sub(R.c(255,types.u8),i) end}

local IP_inv = C.linearPipeline({G.AXIReadBurst{ "frame_128.raw", {128,32}, types.u8, 8, noc.read2, SDF{1,(128*32)/8} },G.HS{G.Map{Inv}},G.AXIWriteBurst{"out/soc_simple",noc.write2}},"IP_inv")

local PTop = G.Module{"PTop",
  function(i)
    local st = G.FanOut{2}(regs:start(i))
    local done_plus200, done_inv = IP_plus200(st[0]), IP_inv(st[1])
    done_plus200 = G.FIFO{128}(done_plus200)
    done_inv = G.FIFO{128}(done_inv)
    
    -- zynq noc master ports are 32bit, but our slave is 64, so resize
    local noc_read0_32 = Pulpino.AXIReadBusResize(noc.read0,32,64)
    local noc_write0_32 = Pulpino.AXIWriteBusResize(noc.write0,32,64)
    
    return R.statements{
      regs:done(G.FanIn(done_plus200,done_inv)),
      noc:readSink0(zynqNOC:read(noc:readSource0())),
      noc:writeSink0(zynqNOC:write(noc:writeSource0())),
      zynqNOC:readSink(noc_read0_32(zynqNOC:readSource())),
      zynqNOC:writeSink(noc_write0_32(zynqNOC:writeSource()))
    }
  end}

harness(PTop)
