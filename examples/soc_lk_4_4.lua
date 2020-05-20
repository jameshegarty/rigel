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

local outfile = "soc_lk_"..CONVWIDTH.."_"..(V*CONVWIDTH)
io.output("out/"..outfile..".design.txt"); io.write("Lucas Kanade "..H.." "..CONVWIDTH.."x"..CONVWIDTH); io.close()
io.output("out/"..outfile..".designT.txt"); io.write(V); io.close()
io.output("out/"..outfile..".dataset.txt"); io.write("SIG20_zu9"); io.close()

local cycles = (W*H)/V
print("CYCLES",cycles)

local regs = SOC.axiRegs({},SDF{1,cycles}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}} ):instantiate("ZynqNOC")
noc.extern=true

--local Fdenom = G.SchedulableFunction{"Fdenom", T.Array2d(P.NumberType("ty"),4),true,
local Fdenom = G.Fmap{G.Function{"Fdenom", T.rv(T.Array2d(types.Int(20,-2),4)),
  function(i)
    print("FDENOM",i.type)
--    local iFO = G.FanOut{4}(i)
    local lhs = G.MulE(i[0],i[3])
    local rhs = G.MulE(i[1],i[2])
    local fdenom = G.SubE(lhs,rhs)

    fdenom = G.RemoveMSBs{bits.inv22inp[1]}(fdenom)
    fdenom = G.RemoveLSBsE{bits.inv22inp[2]}(fdenom)
    print("FDENOMOUT",fdenom.type)
    return fdenom
end}}

--local Fout = G.SchedulableFunction{"Fout", T.tuple{T.array2d(P.NumberType("AType"),4), P.NumberType("fdet_type")},
local Fout = G.Fmap{G.Function{"Fout", T.rv(T.tuple{T.array2d(T.Int(20,-2),4), T.Int(40,-35-bits.inv22inp[2])}),
  function(i)
    print("FOUT",i.type)
    local fmatrix = G.FanOut{4}(i[0])
    local i0 = G.RVFIFO{128}(fmatrix[0][0])
    local i1 = G.RVFIFO{128}(fmatrix[1][1])
    local i2 = G.RVFIFO{128}(fmatrix[2][2])
    local i3 = G.RVFIFO{128}(fmatrix[3][3])
    local fdet = G.FanOut{4}(i[1])

    local OT = {G.MulE(G.RVFIFO{128}(fdet[0]),i3),
                G.MulE(G.Neg(G.RVFIFO{128}(fdet[1])),i1),
                G.MulE(G.Neg(G.RVFIFO{128}(fdet[2])),i2),
                G.MulE(G.RVFIFO{128}(fdet[3]),i0)}

    for k,v in pairs(OT) do
      OT[k] = G.RemoveMSBs{bits.inv22[1]}(OT[k])
      OT[k] = G.RemoveLSBsE{bits.inv22[2]}(OT[k])
    end
    
    return G.TupleToArray(unpack(OT))
end}}

--local Invert2x2 = G.SchedulableFunction{"Invert2x2", T.Array2d(P.NumberType("A"),4),
local Invert2x2 = G.Fmap{G.Function{"Invert2x2", T.rv(T.Array2d(T.int(20,-2),4)),
  function(i)
    print("INV",i.type)
    local iFO = G.FanOut{2}(i)
    local denom = Fdenom( G.RVFIFO{128}(iFO[0]) )
    print("DENOM.ty",denom.type)
    local det = G.Fmap{C.lutinvert(denom.type:deInterface())}(denom)
    local res = Fout( G.RVFIFO{128}(iFO[1]), det )
    return res
end}}

--local Dx = G.SchedulableFunction{"Dx",T.Array2d(T.Uint(8),3),
local Dx = G.Fmap{G.Function{"Dx", T.rv(T.Array2d(T.Uint(8),3)),
  function(i)
    local iFO = G.FanOut{2}(i)
    local outl = G.UtoI(G.AddMSBs{1}(iFO[0][2]))
    local outr = G.UtoI(G.AddMSBs{1}(iFO[1][0]))
    local outt = G.SubE(outl,outr)
    local out = G.RshiftE{1}(outt)
    return out
end}}

--local Dy = G.SchedulableFunction{"Dy", types.array2d(types.uint(8),1,3),
local Dy = G.Fmap{G.Function{"Dy", T.rv(types.array2d(types.uint(8),1,3)),
  function(i)
    local iFO = G.FanOut{2}(i)
    local outl = G.UtoI(G.AddMSBs{1}(G.Index{{0,2}}(iFO[0])))
    local outr = G.UtoI(G.AddMSBs{1}(G.Index{{0,0}}(iFO[1])))
    local outt = G.SubE(outl,outr)
    return G.RshiftE{1}(outt)
end}}

local CalcA = G.SchedulableFunction{"CalcA",
  types.tuple{ types.array2d( P.NumberType("ty"), P.SizeValue("sz")),
               types.array2d( P.NumberType("ty"), P.SizeValue("sz")) },
  function(inp)
    print("CALCA",inp.type)
    local inpFO = G.FanOut{2}(inp)
    
    local Fdx = inpFO[0][0]
    local FdxFO = G.FanOut{3}(Fdx)
    local Fdy = inpFO[1][1]
    local FdyFO = G.FanOut{3}(Fdy)

    local inp0 = G.Zip(G.RVFIFO{128}(FdxFO[0]),G.RVFIFO{128}(FdxFO[1]))
    local out0 = G.Map{G.MulE}(inp0)
    
    out0 = G.Reduce{G.Add{R.Async}}(out0)
    
    local inp1 = G.Zip(G.RVFIFO{128}(FdxFO[2]),G.RVFIFO{128}(FdyFO[0]))
    local out1 = G.Map{G.MulE}(inp1)
    out1 = G.Reduce{G.Add{R.Async}}(out1)
    
    --local out2 = out1
    local out1FO = G.FanOut{2}(out1)
    
    local inp3 = G.Zip(G.RVFIFO{128}(FdyFO[1]),G.RVFIFO{128}(FdyFO[2]))
    local out3 = G.Map{G.MulE}(inp3)
    out3 = G.Reduce{G.Add{R.Async}}(out3)
    
    local out = R.concat{out0,G.RVFIFO{128}(out1FO[0]),G.RVFIFO{128}(out1FO[1]),out3}
    
    return G.TupleToArray(G.FanIn(out))
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
    local iFO = G.FanOut{4}(i)
    local frame0 = iFO[0][0]
    local frame1 = iFO[1][1]
    local Fdx = iFO[2][2]
    local Fdy = iFO[3][3]

    ---------
    local gmf = R.concat("mfgmf",{G.RVFIFO{128}(frame1),G.RVFIFO{128}(frame0)})
    gmf = G.Zip(gmf)
    gmf = G.Map{Minus}(gmf)
    local gmfFO = G.FanOut{2}(gmf)
    ---------

    local out_0 = R.concat("o0tup",{G.RVFIFO{128}(Fdx), G.RVFIFO{128}(gmfFO[0]) })
    out_0 = G.Zip(out_0)
    out_0 = G.Map{G.MulE}(out_0)
    out_0 = G.Reduce{G.Add{R.Async}}(out_0)

    local out_1 = R.concat("o1tup",{G.RVFIFO{128}(Fdy), G.RVFIFO{128}(gmfFO[1]) })
    out_1 = G.Zip(out_1)
    out_1 = G.Map{G.MulE}(out_1)
    out_1 = G.Reduce{G.Add{R.Async}}(out_1)
  
    local out = G.FanIn(out_0,out_1)
    out = G.TupleToArray(out)
    
    return out
end}

--local Solve = G.SchedulableFunction{"Solve", T.Tuple{T.Array2d(P.NumberType("AinvType"),4),T.Array2d(P.NumberType("btype"),2)},
local Solve = G.Fmap{G.Function{"Solve", T.rv(T.Tuple{T.Array2d(T.Int(19,-11-bits.inv22inp[2]),4),T.Array2d(T.Int(20,-1),2)}),
  function(i)
    print("SOLVE",i.type)
    local iFO = G.FanOut{2}(i)
    local Ainv = G.FanOut{4}(iFO[0][0])
    local b = G.FanOut{2}(iFO[1][1])
    local b0, b1 = b[0][0], b[1][1]
    b0 = G.FanOut{2}(G.Neg(b0))
    b1 = G.FanOut{2}(G.Neg(b1))
    local Ainv0, Ainv1, Ainv2, Ainv3 = G.RVFIFO{128}(Ainv[0][0]), G.RVFIFO{128}(Ainv[1][1]), G.RVFIFO{128}(Ainv[2][2]), G.RVFIFO{128}(Ainv[3][3])

    local out_0_lhs = G.MulE( G.RVFIFO{128}(Ainv0), G.RVFIFO{128}(b0[0]) )
    local out_0_rhs = G.MulE( G.RVFIFO{128}(Ainv1), G.RVFIFO{128}(b1[0]) )
    local out_0 = G.AddE( out_0_lhs, out_0_rhs )
    
    local out_1_lhs = G.MulE( G.RVFIFO{128}(Ainv2), G.RVFIFO{128}(b0[1]) )
    local out_1_rhs = G.MulE( G.RVFIFO{128}(Ainv3), G.RVFIFO{128}(b1[1]) )
    local out_1 = G.AddE(out_1_lhs,out_1_rhs)
    
    return G.TupleToArray(out_0,out_1)
end}}

--local Display = G.SchedulableFunction{"Display", T.Array2d(P.NumberType("ity"),2),
local Display = G.Fmap{G.Function{"Display", T.rv(T.Array2d(T.Int(40,-12-bits.inv22inp[2]),2)),
  function(inp)
    print("DISPLAY",inp.type)
    local inpFO = G.FanOut{2}(inp)
    
    local out = {}
    for i=0,1 do
      local I = inpFO[i][i]
      local B = G.MulE{32}(I)

      local FF = G.AddE{128}(B)

      FF = G.Abs(FF)
      FF = G.ItoU(FF)

      local FF_den = G.Denormalize(FF)

      local FF_trunc = G.RemoveMSBs{FF_den.type:deInterface().precision-8}(FF_den)
      --J.err(FF_trunc.type:deInterface()==T.U8,"FF_trunc is:",FF_trunc.type,FF_trunc.scheduleConstraints)
      
      table.insert(out,FF_trunc)
    end

    local res = G.TupleToArray(unpack(out))

    return res
end}}

local LK = G.SchedulableFunction{"LK",types.Array2d(types.array2d(types.uint(8),2),P.SizeValue("imsize")),
    function(inp)

      local inpFO = G.FanOut{2}(inp)
      
      local frame0 = G.Map{G.Index{0}}(inpFO[0])
      local frame1 = G.Map{G.Index{1}}(inpFO[1])
  
      local lb0 = G.Stencil{{-CONVWIDTH, 0, -CONVWIDTH, 0}}(frame0)
      local lb0FO = G.FanOut{3}(lb0)
      local lb1 = G.Stencil{{-CONVWIDTH, 0, -CONVWIDTH, 0}}(frame1)

      local fdx = G.Map{G.Slice{{CONVWIDTH-2, CONVWIDTH, CONVWIDTH-1, CONVWIDTH-1}}}(lb0FO[0])

      fdx = G.Map{Dx}(fdx)

      local fdx_stencil = G.Stencil{{-CONVWIDTH+1, 0, -CONVWIDTH+1, 0}}(fdx)
      local fdx_stencilFO = G.FanOut{2,R.Unoptimized}(fdx_stencil)
      
      local fdy = G.Map{G.Slice{{CONVWIDTH-1, CONVWIDTH-1, CONVWIDTH-2, CONVWIDTH}}}(lb0FO[1])

      local fdy = G.Map{Dy}(fdy)
      local fdy_stencil = G.Stencil{{-CONVWIDTH+1, 0, -CONVWIDTH+1, 0}}(fdy)
      local fdy_stencilFO = G.FanOut{2,R.Unoptimized}(fdy_stencil)
      
      local Ainpinp = R.concat{ G.RVFIFO{128}(fdx_stencilFO[0]), G.RVFIFO{128}(fdy_stencilFO[0]) }
      print("AINPINP",Ainpinp.type,Ainpinp.rate)
      local Ainp = G.Zip{R.Unoptimized}( Ainpinp  )
      local A = G.Map{CalcA}(Ainp)

      local Ainv = G.Map{Invert2x2}(A)

      local f0_slice = G.Map{G.Slice{{0, CONVWIDTH-1, 0, CONVWIDTH-1}}}(lb0FO[2])
      local f1_slice = G.Map{G.Slice{{0, CONVWIDTH-1, 0, CONVWIDTH-1}}}(lb1)

      local binp = G.FanIn{R.Unoptimized}( G.RVFIFO{128,R.Unoptimized}(f0_slice), G.RVFIFO{128,R.Unoptimized}(f1_slice), G.RVFIFO{128,R.Unoptimized}(fdx_stencilFO[1]), G.RVFIFO{128,R.Unoptimized}(fdy_stencilFO[1]) )
      local binp = G.Zip{R.Unoptimized}( binp  )
      local b = G.Map{CalcB}(binp)

      local zipcc = R.concat{Ainv,b}
      zipcc = G.FanIn{R.Unoptimized}(zipcc)
      local sinp = G.Zip{R.Unoptimized}(zipcc)
      local vectorField = G.Map{Solve}(sinp)

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
