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


-- axiRegs expects 32 bit port
local regs = SOC.axiRegs( {}, SDF{1,(128*64)/8} ):instantiate("regs")
--local regs_read_32 = Pulpino.AXIReadBusResize(regs.read,64,32)
--local regs_write_32 = Pulpino.AXIWriteBusResize(regs.write,64,32)



-- zynq noc master ports are 32bit, but our slave is 64, so resize
--local noc_read0_32 = Pulpino.AXIReadBusResize(noc.read,32,64):instantiate("ZynqNOC_NOCSLV_read")
--local noc_write0_32 = Pulpino.AXIWriteBusResize(noc.write,32,64):instantiate("ZynqNOC_NOC_SLV_write")

local ZynqNOC = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}) -- needs to instantiate pulp noc, but not finalize
local zynqNOC = ZynqNOC:instantiate("ZynqNOC")
zynqNOC.extern=true

local noc = Pulpino.AXIInterconnect(2,2,{{zynqNOC.read,zynqNOC.write}}):instantiate("PulpinoNOC")

--noc:addSlaveRead(ZynqNoc.read)
--noc:addSlaveWrite(ZynqNoc.write)

print(ZynqNOC)

local IP_plus200 = C.linearPipeline({G.AXIReadBurst{ "frame_128.raw", {128,32}, types.u8, 8, noc.read, SDF{1,(128*32)/8}, R.Address(0x30008000) },G.MapFramed{G.FIFO{512}},G.HS{G.Map{G.Add{200}}},G.AXIWriteBurst{"out/soc_simple_plus200",noc.write, R.Address(0x3000C000)} },"IP_plus100")

local Inv = G.Module{"Inv",types.u(8),SDF{1,1},function(i) return G.Sub(R.c(255,types.u8),i) end}

local IP_inv = C.linearPipeline({G.AXIReadBurst{ "frame_128.raw", {128,32}, types.u8, 8, noc.read1, SDF{1,(128*32)/8}, R.Address(0x3000A000) },G.MapFramed{G.FIFO{512}},G.HS{G.Map{G.Add{100}}},G.HS{G.Map{G.Add{100}}},G.AXIWriteBurst{"out/soc_simple_inv",noc.write1, R.Address(0x3000D000)}},"IP_inv")

local PTop = G.Module{"PTop",types.HandshakeTrigger,
  function(i)
    local st = G.FanOut{2}(i)
    local done_plus200, done_inv = IP_plus200(st[0]), IP_inv(st[1])
    done_plus200 = G.FIFO{128}(done_plus200)
    done_inv = G.FIFO{128}(done_inv)
    
    
    --    return regs:done(G.FanIn(done_plus200,done_inv))
    return G.FanIn(done_plus200,done_inv)
  end}

print(PTop)

print(noc.module)

local Top = C.linearPipeline({regs.start,PTop,regs.done},"Top",nil,{regs,noc})

Top.globalMetadata.InstCall_PulpinoNOC_write1_write_filename=nil
Top.globalMetadata.InstCall_PulpinoNOC_write_write_filename="out/soc_pulpino_noc"
Top.globalMetadata.InstCall_PulpinoNOC_write_write_H=64

print(Top)
--harness({regs.start,PTop,regs.done},nil,{regs,noc})
harness(Top)
