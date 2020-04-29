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

function toUint8Sign(ty)
  assert(f.FLOAT or f.extractSigned(ty))
  local inp = f.parameter("touint8",ty)
  local outtype = types.array2d(types.uint(8),2)
  local out = f.select(inp:sign(),f.plainconstant({255,255},outtype), f.plainconstant({0,0},outtype))
  return out:toRigelModule("toUint8")
end

function toUint8(ty)
  local inp = f.parameter("touint8",ty)

  if f.FLOAT then
    local out = inp*f.constant(2^10)
    local out = out:lower(types.uint(8))
    local out = f.array2d({out,out},2)
    return out:toRigelModule("toUint8")
  else
    inp = inp*f.constant(2^10,inp:isSigned())
    local out = inp:abs():denormalize():truncate(8):lower()
    local out = f.array2d({out,out},2)
    return out:toRigelModule("toUint8")
  end
end

-- note that we use our convetion here:
-- Atype: type of entries of A matrix
invert2x2 = J.memoize(function( AType, bits )
  assert(type(bits)=="table")

  f.expectFixed(AType)
  local inp = R.input( types.rv(types.Par(types.array2d(AType,4))) )
  local out, output_type
  local cost = 0

  if f.FLOAT then
    local finp = f.parameter( "finp", types.array2d(AType,4) )
    local fdenom = (finp:index(0)*finp:index(3))-(finp:index(1)*finp:index(2))
    local fdet = fdenom:invert()
    local fout = f.array2d({fdet*finp:index(3), (fdet:neg())*(finp:index(1)), (fdet:neg())*(finp:index(2)), fdet*finp:index(0)},4)
    out = R.apply("out", fout:toRigelModule("fout"), inp)
    output_type = types.float(32)
  else
    --------
    local finp = f.parameter( "finp", types.array2d(AType,4) )
    local fdenom = ((finp:index(0):hist("matrix0"))*finp:index(3))-(finp:index(1)*finp:index(2))

    bits.inv22inp[3] = fdenom:precision()
    fdenom = fdenom:reduceBits(bits.inv22inp[1],bits.inv22inp[2])
    fdenom = fdenom:hist("fdenom")
    local fdenom_type = fdenom.type
    print("FDENOM_TYPE",fdenom_type,AType)
    cost = cost + fdenom:cost()
    fdenom = fdenom:toRigelModule("denom")
    --------
    
    local denom = R.apply("denom", fdenom, inp)
    local fdetfn, fdet_type = C.lutinvert(fdenom_type)
    local det = R.apply("det", fdetfn, denom)
    
    ---------
    local finp = f.parameter( "finpt", types.tuple{types.array2d(AType,4), fdet_type:extractData()} )
    local fmatrix = finp:index(0)
    local fdet = finp:index(1)

    local OT = {(fdet*fmatrix:index(3)):hist("invert2x2_output0"), ((fdet:neg())*fmatrix:index(1)), ((fdet:neg())*fmatrix:index(2)), (fdet*fmatrix:index(0))}

    for k,v in pairs(OT) do
      bits.inv22[3] = OT[k]:precision()
      OT[k] = v:reduceBits(bits.inv22[1],bits.inv22[2])
    end

    output_type = OT[1].type

    local fout = f.array2d(OT,4)
    cost = cost + fout:cost()
    ---------
    out = R.apply("out", fout:toRigelModule("fout"), R.concat("ftupp",{inp,det}))
  end

  --print("invert2x2 output type:", output_type)
  return {RM.lambda("invert2x2", inp, out ), output_type, cost}
end)

dx = J.memoize(function(bits)
  assert(type(bits)=="table")

  local inp = f.parameter("dxinp", types.array2d(types.uint(8),3,1))
  local out = ((inp:index(2):lift(0):toSigned()) - (inp:index(0):lift(0):toSigned())):rshift(1)
  bits.d[3] = out:precision()
  out = out:reduceBits(bits.d[1],bits.d[2])
  return {out:toRigelModule("dx"), out.type, out:cost()}
end)

dy = J.memoize(function(bits)
  assert(type(bits)=="table")

  local inp = f.parameter("dyinp", types.array2d(types.uint(8),1,3))
  local out = ((inp:index(0,2):lift(0):toSigned()) - (inp:index(0,0):lift(0):toSigned())):rshift(1)
  bits.d[3] = out:precision()
  return out:reduceBits(bits.d[1],bits.d[2]):toRigelModule("dy")
end)

makePartial = J.memoize(function(ltype,rtype,outMSB,outLSB)
  f.expectFixed(ltype)
  f.expectFixed(rtype)
  assert(type(outMSB)=="number")
  assert(type(outLSB)=="number")

  local finp = f.parameter("pi",types.tuple{ltype,rtype})
  local out = finp:index(0)*finp:index(1)
  local prec = out:precision()
  out = out:reduceBits(outMSB,outLSB)
  --print("OUT:COST",out:cost())
  return {out:toRigelModule("partial_"..tostring(ltype)..tostring(rtype)), out.type, prec, out:cost()}
                      end)

makeSumReduce = J.memoize(function(inputType)
                          assert(types.isType(inputType))
  --print("MakeReduceSum",inputType)
  local finp = f.parameter("pi",types.tuple{inputType,inputType})
  local inp0 = finp:index(0)
  local O = (inp0+finp:index(1)):truncate(inp0:precision())
  return {O:toRigelModule("rsum_"..tostring(inputType)),O:cost()}
                        end)

-- dType: type of derivative
function makeA( dType, window, bits )
  f.expectFixed( dType )
  assert(type(bits)=="table")

  assert(type(window)=="number")

  local cost = 0

  local stt = types.array2d(dType, window, window)
  local inpt = types.tuple{ stt, stt }
  local inp = R.input( types.rv(types.Par(inpt)) )
  local Fdx = R.apply("fdx", C.index(inpt,0), inp)
  local Fdy = R.apply("fdy", C.index(inpt,1), inp)

  local partial = makePartial( dType, dType, bits.Apartial[1], bits.Apartial[2] )
  bits.Apartial[3] = partial[3]
  local partial_type=partial[2]
  local partialfn = partial[1]
  --print("A partial type", partial_type, partial[4])
  cost = cost + partial[4]*3*window*window
  local rsum = makeSumReduce(partial_type)
  cost = cost + rsum[2]*3*window*window
  local rsumfn = rsum[1]

  local inp0 = R.apply("inp0", C.SoAtoAoS(window,window,{dType,dType}), R.concat("o0",{Fdx,Fdx}) )
  local out0 = R.apply("out0", RM.map(partialfn, window, window), inp0 )
  local out0 = R.apply("out0red", RM.reduce(rsumfn, window, window), out0 )

  local inp1 = R.apply("inp1", C.SoAtoAoS(window,window,{dType,dType}), R.concat("o1",{Fdx,Fdy}) )
  local out1 = R.apply("out1", RM.map(partialfn, window, window), inp1 )
  local out1 = R.apply("out1red", RM.reduce(rsumfn, window, window), out1 )

  local out2 = out1

  local inp3 = R.apply("inp3", C.SoAtoAoS(window,window,{dType,dType}), R.concat("o3",{Fdy,Fdy}) )
  local out3 = R.apply("out3", RM.map(partialfn, window, window), inp3 )
  local out3 = R.apply("out3red", RM.reduce(rsumfn, window, window), out3 )

  local out = R.concatArray2d("out", {out0,out1,out2,out3}, 4 )

  return RM.lambda("A", inp, out ), partial_type, cost
end

minus = J.memoize(function(ty)
  assert(types.isType(ty))
  local inp = f.parameter("minux_inp",types.tuple{ty,ty})
  local out = inp:index(0):lift(0):toSigned()-inp:index(1):lift(0):toSigned()
  return {out:toRigelModule("minus"), out.type, out:cost()}
end)

function makeB( dtype, window, bits )
  f.expectFixed(dtype)
  assert(type(window)=="number")
  assert(type(bits)=="table")

  local cost = 0

  -- arguments: frame1, frame2, fdx, fdy
  local FTYPE = types.array2d(types.uint(8),window,window)
  local DTYPE = types.array2d(dtype,window,window)
  local ITYPE = types.tuple{ FTYPE, FTYPE, DTYPE, DTYPE }
  local finp = R.input( types.rv(types.Par(ITYPE)) )
  
  local frame0 = R.apply("frame0", C.index(ITYPE,0), finp)
  local frame1 = R.apply("frame1", C.index(ITYPE,1), finp)
  local Fdx = R.apply("fdx", C.index(ITYPE,2), finp)
  local Fdy = R.apply("fdy", C.index(ITYPE,3), finp)

  ---------
  local gmf = R.concat("mfgmf",{frame1,frame0})
  gmf = R.apply("SA",C.SoAtoAoS(window, window, {types.uint(8),types.uint(8)}), gmf)
  local MINUS = minus(types.uint(8))
  local m, gmf_type, gmf_cost = MINUS[1], MINUS[2], MINUS[3]
  --print("GMF type", gmf_type)
  cost = cost + gmf_cost*window*window
  gmf = R.apply("SSM",RM.map(m,window,window), gmf)
  ---------

  local partial = makePartial( dtype, gmf_type, bits.Bpartial[1], bits.Bpartial[2] )
  bits.Bpartial[3] = partial[3]
  local partial_type = partial[2]
  --print("MakeB Partial Type",partial_type)
  local partialfn = partial[1]
  cost = cost + partial[4]*2*window*window
  local rsum = makeSumReduce(partial_type)
  local rsumfn = rsum[1]
  cost = cost + rsum[2]*2*window*window

  local out_0 = R.concat("o0tup",{Fdx, gmf})
  local out_0 = R.apply("o0P", C.SoAtoAoS(window,window,{dtype, gmf_type}), out_0)
  local out_0 = R.apply("o0", RM.map(partialfn, window, window), out_0)
  local out_0 = R.apply("out0red", RM.reduce(rsumfn, window, window), out_0 )

  local out_1 = R.concat("o1tup",{Fdy, gmf})
  local out_1 = R.apply("o1P", C.SoAtoAoS(window,window,{dtype,gmf_type}), out_1)
  local out_1 = R.apply("o1", RM.map(partialfn, window, window), out_1)
  local out_1 = R.apply("out1red", RM.reduce(rsumfn, window, window), out_1 )

  local out = R.concatArray2d("arrrrry0t",{out_0,out_1},2)

  --print("B output type", partial_type)
  return RM.lambda("b", finp, out), partial_type, cost
end

solve = J.memoize(function( AinvType, btype, bits )
  assert( types.isType(AinvType) )
  assert( types.isType(btype) )
  assert(type(bits)=="table")

  local inp = f.parameter( "solveinp", types.tuple{types.array2d(AinvType,4), types.array2d(btype,2)} )
  local Ainv = inp:index(0)
  local b = inp:index(1)

  local out_0 = (Ainv:index(0)*(b:index(0):neg())) + (Ainv:index(1)*(b:index(1):neg()))
  bits.solve[3] = out_0:precision()
  out_0 = out_0:reduceBits(bits.solve[1], bits.solve[2])

  local out_1 = (Ainv:index(2)*(b:index(0):neg())) + (Ainv:index(3)*(b:index(1):neg()))
  out_1 = out_1:reduceBits(bits.solve[1], bits.solve[2])

  local out = f.array2d({out_0,out_1},2)
  --print("Solve Output Type", out_0.type,out.type,Ainv.type)
  return {out:toRigelModule("lksolve"), out_0.type, out:cost()}
end)

display = J.memoize(function(inpType)
  f.expectFixed(inpType)

  local inp = f.parameter("displayinp",types.array2d(inpType,2))
  local out = {}
  for i=0,1 do
    local I = inp:index(i)
    local B = I*f.constant(32,true,7,0)
    local FF = (B+f.constant(128,true,9,0)):abs()
    local FF_den = FF:denormalize()
    --print("FFDEN TYPE",FF_den.type)
    local FF_trunc = FF_den:truncate(8)
    --print("FF_trunc", FF_trunc.type)
    table.insert(out, FF_trunc:lower(types.uint(8)))
  end
--  table.insert(out, f.constant(0,true,8,0):lower())
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
      local DD = dx(bits)
      local dx, dType, dxcost = DD[1],DD[2],DD[3]

      fdx = G.Map{dx}(fdx)

      local fdx_stencil = G.Stencil{{-window+1, 0, -window+1, 0}}(fdx)


      local fdy = G.Map{G.Slice{{window-1, window-1, window-2, window}}}(lb0)
      fdy = G.Map{dy(bits)}(fdy)
      local fdy_stencil = G.Stencil{{-window+1, 0, -window+1, 0}}(fdy)

      local Af, AType, Acost = makeA( dType, window, bits )
      local Ainp = G.Zip( fdx_stencil, fdy_stencil )
      local A = G.Map{Af}(Ainp)
      local INVO = invert2x2( AType, bits )
      local fAinv, AInvType = INVO[1], INVO[2]

      local Ainv = G.Map{fAinv}(A)

      local fB, BType, Bcost = makeB( dType, window, bits )
      local f0_slice = G.Map{G.Slice{{0, window-1, 0, window-1}}}(lb0)
      local f1_slice = G.Map{G.Slice{{0, window-1, 0, window-1}}}(lb1)
      local binp = G.Zip(f0_slice,f1_slice,fdx_stencil,fdy_stencil)
      local b = G.Map{fB}(binp)

      local SOLV = solve( AInvType, BType, bits )
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
