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
  d={0,0,0},
  Apartial={0,0,0},
  Bpartial={0,0,0},
  solve={0,0,0}
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

local regs = SOC.axiRegs({},SDF{1,W*H*V}):instantiate("regs")

local noc = Zynq.SimpleNOC(nil,nil,{{regs.read,regs.write}} ):instantiate("ZynqNOC")
noc.extern=true

  local fdenom = J.memoize(function(AType)
    local finp = f.parameter( "finp", types.array2d(AType,4) )
    local i0 = finp:index(0)
    if f.isFixedType(AType)==false then i0=i0:lift() end
    local i1 = finp:index(1)
    if f.isFixedType(AType)==false then i1=i1:lift() end
    local i2 = finp:index(2)
    if f.isFixedType(AType)==false then i2=i2:lift() end
    local i3 = finp:index(3)
    if f.isFixedType(AType)==false then i3=i3:lift() end
    
    local fdenom = ((i0:hist("matrix0"))*i3)-(i1*i2)

    bits.inv22inp[3] = fdenom:precision()
    fdenom = fdenom:reduceBits(bits.inv22inp[1],bits.inv22inp[2])
    fdenom = fdenom:hist("fdenom")
    local fdenom_type = fdenom.type
    print("FDENOM_TYPE",fdenom_type,AType)

    return fdenom:toRigelModule("denom")
  end)

    local fout = J.memoize(function(AType,fdet_type)
      local finp = f.parameter( "finpt", types.tuple{types.array2d(AType,4), fdet_type:extractData()} )
      local fmatrix = finp:index(0)

      local i0 = fmatrix:index(0)
      if f.isFixedType(AType)==false then i0=i0:lift() end
      local i1 = fmatrix:index(1)
      if f.isFixedType(AType)==false then i1=i1:lift() end
      local i2 = fmatrix:index(2)
      if f.isFixedType(AType)==false then i2=i2:lift() end
      local i3 = fmatrix:index(3)
      if f.isFixedType(AType)==false then i3=i3:lift() end

      local fdet = finp:index(1)

      local OT = {(fdet*i3):hist("invert2x2_output0"), ((fdet:neg())*i1), ((fdet:neg())*i2), (fdet*i0)}

      for k,v in pairs(OT) do
        bits.inv22[3] = OT[k]:precision()
        OT[k] = v:reduceBits(bits.inv22[1],bits.inv22[2])
      end

      local fout = f.array2d(OT,4)
      return fout:toRigelModule("fout")
    end)

local Invert2x2 = G.SchedulableFunction{"Invert2x2", T.Array2d(P.NumberType("A"),4),
  function(i)
    local denom = fdenom( i.type:deInterface():arrayOver() )(i)
    local det = C.lutinvert(denom.type:deInterface())(denom)
    return fout( i.type:deInterface():arrayOver(), det.type:deInterface() )( i, det )
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

local solve = J.memoize(function( AinvType, btype, bits )
  assert( types.isType(AinvType) )
  assert( types.isType(btype) )
  assert(type(bits)=="table")

  local inp = f.parameter( "solveinp", types.tuple{types.array2d(AinvType,4), types.array2d(btype,2)} )
  local Ainv = inp:index(0)
  local b = inp:index(1)

  local b0 = b:index(0)

  if f.isFixedType(btype)==false then b0=b0:lift() end
  local b1 = b:index(1)
  if f.isFixedType(btype)==false then b1=b1:lift() end

  local out_0 = (Ainv:index(0)*(b0:neg())) + (Ainv:index(1)*(b1:neg()))
  bits.solve[3] = out_0:precision()
  out_0 = out_0:reduceBits(bits.solve[1], bits.solve[2])

  local out_1 = (Ainv:index(2)*(b0:neg())) + (Ainv:index(3)*(b1:neg()))
  out_1 = out_1:reduceBits(bits.solve[1], bits.solve[2])

  local out = f.array2d({out_0,out_1},2)

  return {out:toRigelModule("lksolve"), out_0.type, out:cost()}
end)

local display = J.memoize(function(inpType)
  f.expectFixed(inpType)

  local inp = f.parameter("displayinp",types.array2d(inpType,2))
  local out = {}
  for i=0,1 do
    local I = inp:index(i)
    local B = I*f.constant(32,true,7,0)
    local FF = (B+f.constant(128,true,9,0)):abs()
    local FF_den = FF:denormalize()

    local FF_trunc = FF_den:truncate(8)

    table.insert(out, FF_trunc:lower(types.uint(8)))
  end

  out = f.array2d(out,2)
  return {out:toRigelModule("display"), out:cost()}
end)

function makeLK( T, internalW, internalH, window, bits )
  assert(type(window)=="number")
  assert(type(bits)=="table")

  print("MAKELK",T,internalW,internalH,window,bits)
  
  local cost = 9

  return G.SchedulableFunction{"LK",types.Array2d(types.array2d(types.uint(8),2),P.SizeValue("imsize")),
    function(inp)
                                 
      local frame0 = G.Map{G.Index{0}}(inp)
      local frame1 = G.Map{G.Index{1}}(inp)
  
      local lb0 = G.Stencil{{-window, 0, -window, 0}}(frame0)
      local lb1 = G.Stencil{{-window, 0, -window, 0}}(frame1)

      local fdx = G.Map{G.Slice{{window-2, window, window-1, window-1}}}(lb0)

      fdx = G.Map{Dx}(fdx)

      local fdx_stencil = G.Stencil{{-window+1, 0, -window+1, 0}}(fdx)

      local fdy = G.Map{G.Slice{{window-1, window-1, window-2, window}}}(lb0)

      local fdy = G.Map{Dy}(fdy)
      local fdy_stencil = G.Stencil{{-window+1, 0, -window+1, 0}}(fdy)

      local Ainp = G.Zip( fdx_stencil, fdy_stencil )
      local A = G.Map{CalcA}(Ainp)

      local Ainv = G.Map{Invert2x2}(A)

      local f0_slice = G.Map{G.Slice{{0, window-1, 0, window-1}}}(lb0)
      local f1_slice = G.Map{G.Slice{{0, window-1, 0, window-1}}}(lb1)
      local binp = G.Zip(f0_slice,f1_slice,fdx_stencil,fdy_stencil)
      local b = G.Map{CalcB}(binp)

      local SOLV = solve( Ainv.type:deInterface():arrayOver():arrayOver(), b.type:deInterface():arrayOver():arrayOver(), bits )
      local fSolve, SolveType, SolveCost = SOLV[1],SOLV[2],SOLV[3]
      local sinp = G.Zip(Ainv,b)
      local vectorField = G.Map{fSolve}(sinp)

      local DISP = display(SolveType)
      local displayfn, displaycost = DISP[1], DISP[2]
      local out = G.Map{displayfn}(vectorField)
      return out
    end}
  
end

local LKTop = G.SchedulableFunction{ "LKTop", T.Trigger,
  function(i)
    local readStream = G.AXIReadBurst{ inputFilename, {W,H}, T.Array2d(T.Uint(8),2), 4, noc.read }(i)

    local PadRadius = CONVWIDTH/2
    local PadRadiusAligned = J.upToNearest(V,CONVWIDTH/2)
    local PadExtra = PadRadiusAligned - PadRadius

    local internalW = W+PadRadiusAligned*2
    local internalH = H+CONVWIDTH+1

    local padded = G.Pad{{PadRadiusAligned, PadRadiusAligned, PadRadius+1, PadRadius}}(readStream)
    local lkfn = makeLK( V, internalW, internalH, CONVWIDTH, bits )
    print("LKFN",lkfn.inputType,lkfn.outputType)
    
    local out = lkfn(padded)
    out = G.Crop{{PadRadius*2+PadExtra, PadExtra, PadRadius*2+1, 0}}(out)
    return G.AXIWriteBurst{"out/soc_lk_"..CONVWIDTH.."_"..(V*CONVWIDTH),noc.write}(out)
  end}

harness({regs.start, LKTop, regs.done},nil,{regs})
