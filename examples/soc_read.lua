local R = require "rigel"
local G = require "generators"
local SOC = require "soc"
local harness = require "harnessSOC"
require "types".export()
local SDF = require "sdf"
local Zynq = require "zynq"

noc = Zynq.SimpleNOC():instantiate("ZynqNOC")
noc.extern=true
local regs = SOC.axiRegs({},SDF{1,30*14*9},noc.readSource,noc.readSink,noc.writeSource,noc.writeSink):instantiate("regs")

PosToAddr = G.Module{ "PosToAddr", ar(u16,2),
  function(loc)
    local i = G.PosSeq{{3,3},0}() -- inner loop from 0...2
    local x, y = G.Add(loc[0],i[0]), G.Add(loc[1],i[1]) -- x=loc.x+i.x, y=loc.y+i.y
    local res = G.Add(x,G.Mul(y,R.constant(128,u16))) -- addr = x + y*W (W=128)
    return G.AddMSBs{16}(res)
  end}

ReadStencilDMA = G.Module{ "ReadStencilDMA", Handshake(ar(u16,2)),
  function(loc)
    local locb = G.HS{G.BroadcastSeq{{3,3},0}}(loc) -- duplicate input (x,y) 9 times
    local addrStream = G.HS{PosToAddr}(locb)
    local pxStream = G.AXIRead{"frame_128.raw",128*64,noc.read}(addrStream)
    local pxArr = G.HS{G.Broadcast{1}}(pxStream) -- convert to array with 1 element
    return G.HS{G.Deser{3*3}}(pxArr) -- Deserialize 9 reads into 9 element array
  end}

ConvTop = G.Module{ "ConvTop", 
  function(i)
    i = G.TriggerBroadcast{30*14}(i)
    local pos = G.HS{G.Pos{{30,14},0}}(i)
    local posScaled = G.HS{G.Map{G.Map{G.Mul{4}}}}(pos) -- mult coords by 4
    local stencil = G.Map{ReadStencilDMA}(posScaled)
    local shifted = G.HS{G.Map{G.Map{G.Rshift{3}}}}(stencil)
    local fin = G.HS{G.Map{G.Reduce{G.Add}}}(shifted)
    return G.AXIWriteBurst{"out/soc_read",noc.write}(fin)
  end}

harness({regs.start, ConvTop, regs.done},nil,{regs})
