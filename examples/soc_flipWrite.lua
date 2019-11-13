local R = require "rigel"
R.export()
require "generators.core".export()
local harness = require "generators.harnessSOC"
local SOC = require "generators.soc"
local C = require "generators.examplescommon"
local SDF = require "sdf"
require "types".export()
local Zynq = require "generators.zynq"
local types = require "types"

local regs = SOC.axiRegs({},SDF{1,1024}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local W,H = 128,64

AddrGen = Generator{SDF{1,1},
  types.rv(types.Par(types.array2d(types.tuple{u16,u16},1))),
  types.rv(types.Par(u32)),
  function(inp)
    local x, y = Index{0}(Index{0}(inp)), Index{1}(Index{0}(inp))
    local resx = AddMSBs{16}(x)
    local resy = Mul( Sub(c(H-1,u(32)),AddMSBs{16}(y)),c(W/8,u(32)) )
    return Add(resx,resy)
  end}

fn = Module{"Top",
  function(inp)
    local o = regs.start(inp)
    o = SOC.readBurst("frame_128.raw",128,64,u(8),8,nil,nil,noc.read)(o)

    local ob = FanOut{2}(o)
    local ob0 = R.selectStream("ob0",ob,0)
    ob0 = FIFO{128}(ob0)
    local ob1 = R.selectStream("ob1",ob,1)
    ob1 = FIFO{128}(ob1)
    ob1 = ValueToTrigger(ob1)
    local posSeqOut = PosSeq{{W/8,H},1}(ob1)
    local addrGenOut = AddrGen(posSeqOut)

    local WRITEMOD = SOC.write("out/soc_flipWrite",128,64,u(8),8,nil,noc.write)
    o = WRITEMOD(addrGenOut,ob0)
    o = TriggerCounter{(W*H)/8}(o)
    o = regs.done(o)
    return o
  end,{regs}}

harness(fn)
