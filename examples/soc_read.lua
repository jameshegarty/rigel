local R = require "rigel"
local G = require "generators.core"
local SOC = require "generators.soc"
local harness = require "generators.harnessSOC"
local types = require "types"
require "types".export()
local SDF = require "sdf"
local Zynq = require "generators.zynq"

local regs = SOC.axiRegs({},SDF{1,30*14*9}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}}):instantiate("ZynqNOC")
noc.extern=true

PosToAddr = G.Function{ "PosToAddr", types.rv(types.Par(ar(u16,2))), SDF{1,1},
  function(loc)
    local i = G.PosSeq{{3,3},0}(G.ValueToTrigger(loc)) -- inner loop from 0...2
    local x, y = G.Add(loc[0],i[0]), G.Add(loc[1],i[1]) -- x=loc.x+i.x, y=loc.y+i.y
    local res = G.Add(x,G.Mul(y,R.constant(128,u16))) -- addr = x + y*W (W=128)
    return G.AddMSBs{16}(res)
  end}

ReadStencilDMA = G.Function{ "ReadStencilDMA", Handshake(types.Par(ar(u16,2))), SDF{1,9},
  function(loc)
    local locb = G.BroadcastSeq{{3*3,1},0}(loc) -- duplicate input (x,y) 9 times
    local addrStream = G.Map{PosToAddr}(locb)
    local pxStream = G.Map{G.AXIRead{"frame_128.raw",128*64,noc.read,types.Uint(8)}}(addrStream)
    return G.Deser{3*3}(pxStream) -- Deserialize 9 reads into 9 element array
  end}

ConvTop = G.Function{ "ConvTop", SDF{1,30*14*9}, types.RV(types.Par(types.Trigger)), 
  function(i)
    local pos = G.Pos{{30,14}}(i)
    local posScaled = G.Map{G.Map{G.Mul{4}}}(pos) -- mult coords by 4
    local stencil = G.Map{ReadStencilDMA}(posScaled)
    local shifted = G.Map{G.Map{G.Rshift{3}}}(stencil)
    local fin = G.Map{G.Reduce{G.Add{R.Async}}}(shifted)
    return G.AXIWriteBurst{"out/soc_read",noc.write}(fin)
  end}

harness({regs.start, ConvTop, regs.done},nil,{regs})
