local R = require "rigel"
local G = require "generators"
local SOC = require "soc"
local harness = require "harnessSOC"
require "types".export()

regs = SOC.axiRegs{}:instantiate()

PosToAddr = G.Module{ "PosToAddr", ar(u16,2),
  function(loc)
    local i = G.PosSeq{{3,3},0}() -- inner loop from 0...2
    local x, y = G.Add(loc[0],i[0]), G.Add(loc[1],i[1]) -- x=loc.x+i.x, y=loc.y+i.y
    local res = G.Add(x,G.Mul(y,R.constant("C",128,u16))) -- addr = x + y*128
    return G.AddMSBs{16}(res)
  end}

print(PosToAddr)

ReadStencilDMA = G.Module{ "ReadStencilDMA", Handshake(ar(u16,2)),
  function(loc)
    local locb = G.HS{G.BroadcastSeq{{3,3},0}}(loc)
    local addrStream = G.HS{PosToAddr}(locb)
    local pxStream = G.AXIRead{"frame_128.raw",128*64}(addrStream)
    print("PXSTRAM",pxStream.type)
--    pxStream = G.HS{G.BtoU}(pxStream)
--    pxStream = G.HS{G.RemoveMSBs{24}}(pxStream)
    local pxArr = G.HS{G.Broadcast{1}}(pxStream) -- convert to array with 1 element
    print("PXARR",pxArr.type)
    local res = G.HS{G.Deser{3*3}}(pxArr)
--    print("RT",res.type)
    return res
  end}

print(ReadStencilDMA)

ConvTop = G.Module{ "ConvTop", 
  function(i)
    i = G.TriggerBroadcast{30*14}(i)
    local pos = G.HS{G.Pos{{30,14},0}}(i)
--    print("POSTYPE",pos.type)
--    print(pos.fn)
    local posScaled = G.HS{G.Map{G.Map{G.Mul{4}}}}(pos) -- mult coords by 4
--    print(posScaled.fn)
    local stencil = G.Map{ReadStencilDMA}(posScaled)
--    print(stencil.fn)
--    print("STTYPE",stencil.type)
    local shifted = G.HS{G.Map{G.Map{G.Rshift{3}}}}(stencil)
--    print(shifted.fn)
    local fin = G.HS{G.Map{G.Reduce{G.Add}}}(shifted)
--    print("FIN",fin.type)
    local res =  G.AXIWriteBurst{"out/soc_read"}(fin)
--    print(res.fn)
    return res
  end}

ConvTopMod = ConvTop{R.HandshakeTrigger}
print(ConvTopMod)

harness{regs.start, ConvTop, regs.done}
