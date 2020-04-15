local R = require "rigel"
local RM = require "generators.modules"
local types = require "types"
local C = require "generators.examplescommon"
local J = require "common"

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
function invert2x2( AType, bits )
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
  return RM.lambda("invert2x2", inp, out ), output_type, cost
end

function dx(bits)
  assert(type(bits)=="table")

  local inp = f.parameter("dxinp", types.array2d(types.uint(8),3,1))
  local out = ((inp:index(2):lift(0):toSigned()) - (inp:index(0):lift(0):toSigned())):rshift(1)
  bits.d[3] = out:precision()
  out = out:reduceBits(bits.d[1],bits.d[2])
  return out:toRigelModule("dx"), out.type, out:cost()
end

function dy(bits)
  assert(type(bits)=="table")

  local inp = f.parameter("dyinp", types.array2d(types.uint(8),1,3))
  local out = ((inp:index(0,2):lift(0):toSigned()) - (inp:index(0,0):lift(0):toSigned())):rshift(1)
  bits.d[3] = out:precision()
  return out:reduceBits(bits.d[1],bits.d[2]):toRigelModule("dy")
end

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

function minus(ty)
  assert(types.isType(ty))
  local inp = f.parameter("minux_inp",types.tuple{ty,ty})
  local out = inp:index(0):lift(0):toSigned()-inp:index(1):lift(0):toSigned()
  return out:toRigelModule("minus"), out.type, out:cost()
end

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
  local m, gmf_type, gmf_cost = minus(types.uint(8))
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

function solve( AinvType, btype, bits )
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
  return out:toRigelModule("lksolve"), out_0.type, out:cost()
end

function display(inpType)
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
  return out:toRigelModule("display"), out:cost()
end

function makeLK( T, internalW, internalH, window, bits )
  assert(type(window)=="number")
  assert(type(bits)=="table")

  local cost = 9

  local INPTYPE = types.array2d(types.uint(8),2)
  local inp = R.input(types.rv(types.Par(types.array2d(INPTYPE,T))))
  local frame0 = R.apply("f0", RM.map(C.index(INPTYPE, 0 ),T), inp)
  local frame1 = R.apply("f1", RM.map(C.index(INPTYPE, 1 ),T), inp)

  local st_type = types.array2d( types.uint(8), window+1, window+1 )

  local lb0 = R.apply("lb0", C.stencilLinebuffer(types.uint(8), internalW, internalH, T, -window, 0, -window, 0 ), frame0)
  local lb0 = R.apply( "lb0_st", C.unpackStencil( types.uint(8), window+1, window+1, T ) , lb0 )
  local lb1 = R.apply("lb1", C.stencilLinebuffer(types.uint(8), internalW, internalH, T, -window, 0, -window, 0 ), frame1)
  local lb1 = R.apply( "lb1_st", C.unpackStencil( types.uint(8), window+1, window+1, T ) , lb1 )

  local fdx = R.apply("slx", RM.map(C.slice( st_type, window-2, window, window-1, window-1),T), lb0)
  local dx, dType, dxcost = dx(bits)
  local fdx = R.apply("fdx", RM.map(dx,T), fdx)

  local fdx_stencil = R.apply("fdx_stencil", C.stencilLinebuffer(dType, internalW, internalH, T, -window+1, 0, -window+1, 0 ), fdx)
  local fdx_stencil = R.apply( "fdx_stencil_st", C.unpackStencil( dType, window, window, T ) , fdx_stencil )

  local fdy = R.apply("sly", RM.map(C.slice( st_type, window-1, window-1, window-2, window),T), lb0)
  local fdy = R.apply("fdy", RM.map(dy(bits),T), fdy )

  local fdy_stencil = R.apply("fdy_stencil", C.stencilLinebuffer(dType, internalW, internalH, T, -window+1, 0, -window+1, 0 ), fdy)
  local fdy_stencil = R.apply( "fdy_stencil_st", C.unpackStencil( dType, window, window, T ) , fdy_stencil )

  cost = cost + dxcost*2

  local dst_type = types.array2d(dType,window,window)
  local Af, AType, Acost = makeA( dType, window, bits )
  local Ainp = R.apply("Ainp", C.SoAtoAoS(T,1,{dst_type,dst_type},false),R.concat("ainp",{fdx_stencil,fdy_stencil}) )
  local A = R.apply("A", RM.map(Af,T), Ainp)
  local fAinv, AInvType = invert2x2( AType, bits )
  local FAINVMAP = RM.map(fAinv,T,1,true)
  local Ainv = R.apply("Ainv", FAINVMAP, A)
  cost = cost + Acost

  local fB, BType, Bcost = makeB( dType, window, bits )
  local f0_slice = R.apply("f0slice", RM.map(C.slice(st_type, 0, window-1, 0, window-1),T), lb0)
  local f1_slice = R.apply("f1slice", RM.map(C.slice(st_type, 0, window-1, 0, window-1),T), lb1)
  local sm_type = types.array2d(types.uint(8),window,window)
  local binp = R.apply("binp", C.SoAtoAoS(T,1,{sm_type,sm_type,dst_type,dst_type}), R.concat("btup",{f0_slice,f1_slice,fdx_stencil,fdy_stencil}))
  local b = R.apply("b", RM.map(fB,T), binp)
  cost = cost + Bcost

  local fSolve, SolveType, SolveCost = solve( AInvType, BType, bits )
  local sinp = R.apply("sinp", C.SoAtoAoS(T,1,{types.array2d(AInvType,4),types.array2d(BType,2)}), R.concat("solveinp",{Ainv,b}))
  local vectorField = R.apply("lksolvemod", RM.map(fSolve,T), sinp)
  cost = cost + SolveCost
  
  local displayfn, displaycost = display(SolveType)
  local out = R.apply("display", RM.map(displayfn,T), vectorField)
  cost = cost + displaycost

  return RM.lambda("LK",inp,out), cost
end

function LKTop(T,W,H,window,bits,nostall,X)
  assert(type(T)=="number")
  assert(T>=1)
  assert(type(bits)=="table")
  assert(type(nostall)=="boolean")
  assert(X==nil)

  local PadRadius = window/2
  local PadRadiusAligned = J.upToNearest(T,window/2)
  local PadExtra = PadRadiusAligned - PadRadius
  --print("PadRadius",PadRadius,"PRA",PadRadiusAligned)

  local internalW = W+PadRadiusAligned*2
  local internalH = H+window+1

  local ITYPE = types.array2d(types.uint(8),2)
  
  local RW_TYPE = types.array2d( ITYPE, 4 ) -- simulate axi bus
  local hsfninp = R.input( R.Handshake(RW_TYPE) )

  local fifos = {}
  local statements = {}

  local out = hsfninp
  if T~=4 then
    out = R.apply("reducerate", RM.liftHandshake(RM.changeRate(types.array2d(types.uint(8),2),1,4,T)), hsfninp )
  end

  local out = R.apply("pad", RM.liftHandshake(RM.padSeq(ITYPE, W, H, T, PadRadiusAligned, PadRadiusAligned, PadRadius+1, PadRadius, {0,0})), out)

  local lkfn, lkcost = makeLK( T, internalW, internalH, window, bits )
  out = R.apply("LK", RM.makeHandshake( lkfn ), out )

  -- FIFO to improve timing
  if false then
  else
    local sz = 128
    if nostall then sz = 2048 end
--    table.insert( fifos, R.instantiateRegistered("f_timing",RM.fifo(types.array2d(ITYPE,T),sz,nostall)) )
--    table.insert( statements, R.applyMethod( "s_timing", fifos[#fifos], "store", out ) )
    --    out = R.applyMethod("r_timing",fifos[#fifos],"load")
    out = C.fifo(types.array2d(ITYPE,T),sz,nostall)(out)
  end

  local out = R.apply("crop",C.cropHelperSeq(ITYPE, internalW, internalH, T, PadRadius*2+PadExtra, PadExtra, PadRadius*2+1, 0), out)
  if T~=4 then
    out = R.apply("incrate", RM.liftHandshake(RM.changeRate(ITYPE,1,T,4)), out )
  end

  table.insert(statements,1,out)

  local hsfn = RM.lambda("hsfn", hsfninp, R.statements(statements), fifos)

  return hsfn, lkcost
end
