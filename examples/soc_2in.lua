local R = require "rigel"
local SOC = require "generators.soc"
local C = require "generators.examplescommon"
local harness = require "generators.harnessSOC"
local RS = require "rigelSimple"
local RM = require "generators.modules"
local G = require "generators.core"
require "types".export()
local SDF = require "sdf"
local Zynq = require "generators.zynq"

local regs = SOC.axiRegs({},SDF{1,1024}):instantiate("regs")

local noc = Zynq.SimpleNOC(2,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

local inp = R.input(R.HandshakeTrigger)
local inpFO = G.FanOut{2}(inp)
local inp0, inp1 = inpFO[0], inpFO[1]
print("INPOFO",inpFO,inp0,inp1)
local a = SOC.readBurst("frame_128.raw",128,64,u(8),8,nil,nil,noc.read)(inp0)
local bb = SOC.readBurst("frame_128_inv.raw",128,64,u(8),8,nil,nil,noc.read1)(inp1)
local out = G.FanIn{true}(a,bb)
out = RS.HS(RM.SoAtoAoS(8,1,{u(8),u(8)}))(out)
out = RS.HS(RM.map(C.sum(u(8),u(8),u(8)),8))(out)
--out = RS.HS(C.cast(ar(u(8),8),b(64)))(out)
out = SOC.writeBurst("out/soc_2in",128,64,u(8),8,1,nil,noc.write)(out)

local fn = RM.lambda("FN",inp,out)
harness({regs.start,fn,regs.done},nil,{regs})
