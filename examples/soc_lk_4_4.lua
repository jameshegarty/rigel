local R = require "rigel"
local T = require "types"
local types = T
local RM = require "generators.modules"
local C = require "generators.examplescommon"
local G = require "generators.core"
local SOC = require "generators.soc"
local SDF = require "sdf"
local Zynq = require "generators.zynq"
local J = require "common"
local harness = require "generators.harnessSOC"
local P = require "params"

local f = require "fixed"

local first,flen = string.find(arg[0],"%d+")
local CONVWIDTH = tonumber(string.sub(arg[0],first,flen))
local V = tonumber(string.sub(arg[0], string.find(arg[0],"%d+",flen+1)))
V = V/CONVWIDTH

print("CONVWIDTH",CONVWIDTH,"V",V)

local bits = {
  inv22={15,26,0},
  inv22inp={5,5,0}, -- NOTICE THIS IS DIFFERENT THAN WINDOW=6 VERSION
--  d={0,0,0},
--  Apartial={0,0,0},
--  Bpartial={0,0,0},
--  solve={0,0,0}
}

local inputFilename = "trivial_64.raw"
local W,H = 64,64
if CONVWIDTH==6 then
  bits.inv22inp={0,10,0}
  inputFilename = "trivial_128.raw"
  W,H = 128,128
elseif CONVWIDTH==12 then
  bits.inv22inp={0,10,0}
  inputFilename = "packed_v0000.raw"
  W,H = 1920,1080
end

local cycles = (W*H)/V
print("CYCLES",cycles)

local regs = SOC.axiRegs({},SDF{1,cycles}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}} ):instantiate("ZynqNOC")
noc.extern=true

local Fdenom = G.SchedulableFunction{"Fdenom", T.Array2d(P.NumberType("ty"),4),
  function(i)
    local lhs = G.MulE(i[0],i[3])
    local rhs = G.MulE(i[1],i[2])
    local fdenom = G.SubE(lhs,rhs)
    fdenom = G.RemoveMSBs{bits.inv22inp[1]}(fdenom)
    fdenom = G.RemoveLSBsE{bits.inv22inp[2]}(fdenom)
    return fdenom
  end}

local Fout = G.SchedulableFunction{"Fout", T.tuple{T.array2d(P.NumberType("AType"),4), P.NumberType("fdet_type")},
  function(i)
    local fmatrix = i[0]
    local i0 = fmatrix[0]
    local i1 = fmatrix[1]
    local i2 = fmatrix[2]
    local i3 = fmatrix[3]
    local fdet = i[1]

    local OT = {G.MulE(fdet,i3), G.MulE(G.Neg(fdet),i1), G.MulE(G.Neg(fdet),i2), G.MulE(fdet,i0)}
    for k,v in pairs(OT) do
      OT[k] = G.RemoveMSBs{bits.inv22[1]}(OT[k])
      OT[k] = G.RemoveLSBsE{bits.inv22[2]}(OT[k])
    end
    return G.TupleToArray(unpack(OT))
end}

local Invert2x2 = G.SchedulableFunction{"Inv", T.Array2d(P.NumberType("A"),4),
  function(i)
    local denom = Fdenom(i)
    local det = C.lutinvert(denom.type:deInterface())(denom)
    local res = Fout(i,det)
    return res
  end}

local Dx = G.SchedulableFunction{"Dx",T.Array2d(T.Uint(8),3),
  function(i)
    local outl = G.UtoI(G.AddMSBs{1}(i[2]))
    local outr = G.UtoI(G.AddMSBs{1}(i[0]))
    local outt = G.SubE(outl,outr)
    local out = G.RshiftE{1}(outt)
    return out
  end}

local Dy = G.SchedulableFunction{"Dy", types.array2d(types.uint(8),1,3),
  function(i)
    local outl = G.UtoI(G.AddMSBs{1}(G.Index{{0,2}}(i)))
    local outr = G.UtoI(G.AddMSBs{1}(G.Index{{0,0}}(i)))
    local outt = G.SubE(outl,outr)
    return G.RshiftE{1}(outt)
  end}

local CalcA = G.SchedulableFunction{"CalcA",
  types.tuple{ types.array2d( P.NumberType("ty"), P.SizeValue("sz")),
               types.array2d( P.NumberType("ty"), P.SizeValue("sz")) },
  function(inp)
    local Fdx = inp[0]
    local Fdy = inp[1]

    local inp0 = G.Zip(Fdx,Fdx)
    local out0 = G.Map{G.MulE}(inp0)
    
    out0 = G.Reduce{G.Add}(out0)
    
    local inp1 = G.Zip(Fdx,Fdy)
    local out1 = G.Map{G.MulE}(inp1)
    out1 = G.Reduce{G.Add}(out1)
    
    local out2 = out1
    
    local inp3 = G.Zip(Fdy,Fdy)
    local out3 = G.Map{G.MulE}(inp3)
    out3 = G.Reduce{G.Add}(out3)
    
    local out = R.concatArray2d("out", {out0,out1,out2,out3}, 4 )
    
    return out
  end}

local Minus = G.SchedulableFunction{"Minus",T.Tuple{P.NumberType("A"),P.NumberType("A")},
  function(i)
    assert( i.type:deInterface().list[1]==i.type:deInterface().list[2] )
    local lhs = G.UtoI(G.AddMSBs{1}(i[0]))
    local rhs = G.UtoI(G.AddMSBs{1}(i[1]))
    return G.SubE(lhs,rhs)
  end}

local CalcB = G.SchedulableFunction{"CalcB",
  T.Tuple{ T.Array2d(T.U8,P.SizeValue("w")), T.Array2d(T.U8,P.SizeValue("w")),
           T.Array2d(P.NumberType("ty"),P.SizeValue("w")),
           T.Array2d(P.NumberType("ty"),P.SizeValue("w")) },
  function(i)                              
    local frame0 = i[0]
    local frame1 = i[1]
    local Fdx = i[2]
    local Fdy = i[3]

    ---------
    local gmf = R.concat("mfgmf",{frame1,frame0})
    gmf = G.Zip(gmf)
    gmf = G.Map{Minus}(gmf)
    ---------

    local out_0 = R.concat("o0tup",{Fdx, gmf})
    out_0 = G.Zip(out_0)
    out_0 = G.Map{G.MulE}(out_0)
    out_0 = G.Reduce{G.Add}(out_0)

    local out_1 = R.concat("o1tup",{Fdy, gmf})
    out_1 = G.Zip(out_1)
    out_1 = G.Map{G.MulE}(out_1)
    out_1 = G.Reduce{G.Add}(out_1)
  
    local out = R.concatArray2d("arrrrry0t",{out_0,out_1},2)
    return out
end}

local Solve = G.SchedulableFunction{"Solve", T.Tuple{T.Array2d(P.NumberType("AinvType"),4),T.Array2d(P.NumberType("btype"),2)},
  function(i)
    local Ainv = i[0]
    local b = i[1]
    local b0, b1 = b[0], b[1]
    b0 = G.Neg(b0)
    b1 = G.Neg(b1)
    local Ainv0, Ainv1, Ainv2, Ainv3 = Ainv[0], Ainv[1], Ainv[2], Ainv[3]

    local out_0_lhs = G.MulE(Ainv0,b0)
    local out_0_rhs = G.MulE(Ainv1,b1)
    local out_0 = G.AddE( out_0_lhs, out_0_rhs )
    
    local out_1_lhs = G.MulE(Ainv2,b0)
    local out_1_rhs = G.MulE(Ainv3,b1)
    local out_1 = G.AddE(out_1_lhs,out_1_rhs)
    
    return G.TupleToArray(out_0,out_1)
  end}

local Display = G.SchedulableFunction{"Display", T.Array2d(P.NumberType("ity"),2),
  function(inp)
    local out = {}
    for i=0,1 do
      local I = inp[i]
      local B = G.MulE{32}(I)

      local FF = G.AddE{128}(B)

      FF = G.Abs(FF)
      FF = G.ItoU(FF)

      local FF_den = G.Denormalize(FF)

      local FF_trunc = G.RemoveMSBs{FF_den.type:deInterface().precision-8}(FF_den)
      assert(FF_trunc.type:deInterface()==T.U8)      

      table.insert(out,FF_trunc)
    end

    local res = G.TupleToArray(unpack(out))

    return res
  end}

local LK = G.SchedulableFunction{"LK",types.Array2d(types.array2d(types.uint(8),2),P.SizeValue("imsize")),
    function(inp)
                                 
      local frame0 = G.Map{G.Index{0}}(inp)
      local frame1 = G.Map{G.Index{1}}(inp)
  
      local lb0 = G.Stencil{{-CONVWIDTH, 0, -CONVWIDTH, 0}}(frame0)
      local lb1 = G.Stencil{{-CONVWIDTH, 0, -CONVWIDTH, 0}}(frame1)

      local fdx = G.Map{G.Slice{{CONVWIDTH-2, CONVWIDTH, CONVWIDTH-1, CONVWIDTH-1}}}(lb0)

      fdx = G.Map{Dx}(fdx)

      local fdx_stencil = G.Stencil{{-CONVWIDTH+1, 0, -CONVWIDTH+1, 0}}(fdx)

      local fdy = G.Map{G.Slice{{CONVWIDTH-1, CONVWIDTH-1, CONVWIDTH-2, CONVWIDTH}}}(lb0)

      local fdy = G.Map{Dy}(fdy)
      local fdy_stencil = G.Stencil{{-CONVWIDTH+1, 0, -CONVWIDTH+1, 0}}(fdy)

      local Ainp = G.Zip( fdx_stencil, fdy_stencil )
      local A = G.Map{CalcA}(Ainp)

      local Ainv = G.Map{Invert2x2}(A)

      local f0_slice = G.Map{G.Slice{{0, CONVWIDTH-1, 0, CONVWIDTH-1}}}(lb0)
      local f1_slice = G.Map{G.Slice{{0, CONVWIDTH-1, 0, CONVWIDTH-1}}}(lb1)
      local binp = G.Zip(f0_slice,f1_slice,fdx_stencil,fdy_stencil)
      local b = G.Map{CalcB}(binp)

      local sinp = G.Zip(Ainv,b)
      local vectorField = G.Map{Solve}(sinp)

      local stype = vectorField.type:deInterface():arrayOver():arrayOver()

      --local DISP = display(stype)
      --local displayfn, displaycost = DISP[1], DISP[2]
      --local out = G.Map{displayfn}(vectorField)
      local out = G.Map{Display}(vectorField)
      
      return out
    end}

local LKTop = G.SchedulableFunction{ "LKTop", T.Trigger,
  function(i)
    local readStream = G.AXIReadBurst{ inputFilename, {W,H}, T.Array2d(T.Uint(8),2), 4, noc.read }(i)

    local PadRadius = CONVWIDTH/2
    local PadRadiusAligned = PadRadius
    if V>1 then
      PadRadiusAligned = J.upToNearest(V,CONVWIDTH/2)
    end
    
    local PadExtra = PadRadiusAligned - PadRadius

    local padded = G.Pad{{PadRadiusAligned, PadRadiusAligned, PadRadius+1, PadRadius}}(readStream)
    
    local out = LK(padded)
    out = G.Crop{{PadRadius*2+PadExtra, PadExtra, PadRadius*2+1, 0}}(out)
    return G.AXIWriteBurst{"out/soc_lk_"..CONVWIDTH.."_"..(V*CONVWIDTH),noc.write}(out)
  end}

harness({regs.start, LKTop, regs.done},nil,{regs})
