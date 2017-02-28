local R = require "rigel"
local types = require "types"
local RM = require "modules"
local C = require "examplescommon"

local function FIFO(fifos,statements,A,inp)
  local id = #fifos
  table.insert( fifos, R.instantiateRegistered("fifo"..tostring(id),RM.fifo(A,128)) )
  table.insert( statements, R.applyMethod("s"..tostring(id),fifos[#fifos],"store",inp) )
  return R.applyMethod("l"..tostring(id),fifos[#fifos],"load")
end

function toUint8Sign(ty)
  assert(f.FLOAT or f.extractSigned(ty))
  local inp = f.parameter("touint8",ty)
  local outtype = types.array2d(types.uint(8),2)
  local out = f.select(inp:sign(),f.plainconstant({255,255},outtype), f.plainconstant({0,0},outtype))
  return out:toDarkroom("toUint8")
end

function toUint8(ty)
  local inp = f.parameter("touint8",ty)

  if f.FLOAT then
    local out = inp*f.constant(2^10)
    local out = out:lower(types.uint(8))
    local out = f.array2d({out,out},2)
    return out:toDarkroom("toUint8")
  else
    inp = inp*f.constant(2^10,inp:isSigned())
    local out = inp:abs():denormalize():truncate(8):lower()
    local out = f.array2d({out,out},2)
    return out:toDarkroom("toUint8")
  end
end

-- note that we use our convetion here:
-- Atype: type of entries of A matrix
function invert2x2( AType, bits )
  assert(type(bits)=="table")

  f.expectFixed(AType)
  local inp = R.input( types.array2d(AType,4) )
  local out, output_type
  local cost = 0

  if f.FLOAT then
    local finp = f.parameter( "finp", types.array2d(AType,4) )
    local fdenom = (finp:index(0)*finp:index(3))-(finp:index(1)*finp:index(2))
    local fdet = fdenom:invert()
    local fout = f.array2d({fdet*finp:index(3), (fdet:neg())*(finp:index(1)), (fdet:neg())*(finp:index(2)), fdet*finp:index(0)},4)
    out = R.apply("out", fout:toDarkroom("fout"), inp)
    output_type = types.float(32)
  else
    --------
    local finp = f.parameter( "finp", types.array2d(AType,4) )
    local fdenom = ((finp:index(0):hist("matrix0"))*finp:index(3))-(finp:index(1)*finp:index(2))
    --print(fdenom.type,"SDFSDF") 41 2^-4
    --fdenom = fdenom:normalize(31)
    bits.inv22inp[3] = fdenom:precision()
    fdenom = fdenom:reduceBits(bits.inv22inp[1],bits.inv22inp[2])
    fdenom = fdenom:hist("fdenom")
    local fdenom_type = fdenom.type
    cost = cost + fdenom:cost()
    fdenom = fdenom:toDarkroom("denom")
    --------
    
    local denom = R.apply("denom", fdenom, inp)
    local fdetfn, fdet_type = C.lutinvert(fdenom_type)
    local det = R.apply("det", fdetfn, denom)
    
    ---------
    local finp = f.parameter( "finpt", types.tuple{types.array2d(AType,4), fdet_type} )
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
    out = R.apply("out", fout:toDarkroom("fout"), R.tuple("ftupp",{inp,det}))
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
  return out:toDarkroom("dx"), out.type, out:cost()
end

function dy(bits)
  assert(type(bits)=="table")

  local inp = f.parameter("dyinp", types.array2d(types.uint(8),1,3))
  local out = ((inp:index(0,2):lift(0):toSigned()) - (inp:index(0,0):lift(0):toSigned())):rshift(1)
  bits.d[3] = out:precision()
  return out:reduceBits(bits.d[1],bits.d[2]):toDarkroom("dy")
end

makePartial = memoize(function(ltype,rtype,outMSB,outLSB)
  f.expectFixed(ltype)
  f.expectFixed(rtype)
  assert(type(outMSB)=="number")
  assert(type(outLSB)=="number")

  local finp = f.parameter("pi",types.tuple{ltype,rtype})
  local out = finp:index(0)*finp:index(1)
  local prec = out:precision()
  out = out:reduceBits(outMSB,outLSB)
  --print("OUT:COST",out:cost())
  return {out:toDarkroom("partial_"..tostring(ltype)..tostring(rtype).."_"..outMSB.."_"..outLSB), out.type, prec, out:cost()}
                      end)

makeSumReduce = memoize(function(inputType,async)
                          assert(types.isType(inputType))
                          assert(type(async)=="boolean")

  --print("MakeReduceSum",inputType)
  local finp = f.parameter("pi",types.tuple{inputType,inputType})
  local inp0 = finp:index(0)
  local O = (inp0+finp:index(1)):truncate(inp0:precision())
  if async then O = O:disablePipelining() end
  return O:toDarkroom("rsum_"..tostring(inputType).."_async"..tostring(async))
                        end)

-- dType: type of derivative
function makeA( T, dType, window, bits )
  assert(type(T)=="number")
  assert(T<=1)
  assert(window*T == math.floor(window*T))

  f.expectFixed( dType )
  assert(type(bits)=="table")

  assert(type(window)=="number")

  local stt = types.array2d(dType, window*T, window)
  local inpt = types.tuple{ stt, stt }
  local inp = R.input( R.Handshake(inpt) )
  local Fdx = R.apply("fdx", RM.makeHandshake(C.index(inpt,0)), inp)
  local Fdy = R.apply("fdy", RM.makeHandshake(C.index(inpt,1)), inp)

  local partial = makePartial( dType, dType, bits.Apartial[1], bits.Apartial[2] )
  bits.Apartial[3] = partial[3]
  local partial_type=partial[2]
  local partialfn = partial[1]
  --print("A partial type", partial_type, partial[4])

  local rsumfn = makeSumReduce(partial_type,false)
  local rsumAsyncfn = makeSumReduce(partial_type,true)

  local inp0 = R.apply("inp0", C.SoAtoAoSHandshake(window*T,window,{dType,dType}), R.tuple("o0",{Fdx,Fdx},false) )
  local out0 = R.apply("out0", RM.makeHandshake(RM.map(partialfn, window*T, window)), inp0 )
  local out0 = R.apply("out0red", RM.makeHandshake(RM.reduce(rsumfn, window*T, window)), out0 )
  local out0 = R.apply("out0redseq", RM.liftHandshake(RM.liftDecimate(RM.reduceSeq( rsumAsyncfn, T ))), out0 )

  local inp1 = R.apply("inp1", C.SoAtoAoSHandshake(window*T,window,{dType,dType}), R.tuple("o1",{Fdx,Fdy},false) )
  local out1 = R.apply("out1", RM.makeHandshake(RM.map(partialfn, window*T, window)), inp1 )
  local out1 = R.apply("out1red", RM.makeHandshake(RM.reduce(rsumfn, window*T, window)), out1 )
  local out1 = R.apply("out1redseq", RM.liftHandshake(RM.liftDecimate(RM.reduceSeq( rsumAsyncfn, T ))), out1 )

  local out2 = out1

  local inp3 = R.apply("inp3", C.SoAtoAoSHandshake(window*T,window,{dType,dType}), R.tuple("o3",{Fdy,Fdy},false) )
  local out3 = R.apply("out3", RM.makeHandshake(RM.map(partialfn, window*T, window)), inp3 )
  local out3 = R.apply("out3red", RM.makeHandshake(RM.reduce(rsumfn, window*T, window)), out3 )
  local out3 = R.apply("out3redseq", RM.liftHandshake(RM.liftDecimate(RM.reduceSeq( rsumAsyncfn, T ))), out3 )

  local out = R.tuple("out", {out0,out1,out2,out3},false )
  out = R.apply("PT",RM.packTuple({partial_type,partial_type,partial_type,partial_type}),out)
  out = R.apply("PTC",RM.makeHandshake(C.tupleToArray(partial_type,4)),out)

  return RM.lambda("A", inp, out ), partial_type
end

function minus(ty)
  assert(types.isType(ty))
  local inp = f.parameter("minux_inp",types.tuple{ty,ty})
  local out = inp:index(0):lift(0):toSigned()-inp:index(1):lift(0):toSigned()
  return out:toDarkroom("minus"), out.type, out:cost()
end

function makeB( T, dtype, window, bits )
  f.expectFixed(dtype)
  assert(type(window)=="number")
  assert(type(bits)=="table")

  assert(T<=1)
  assert(window*T == math.floor(window*T))

  local fifos = {}
  local statements = {}

  local cost = 0

  -- arguments: frame1, frame2, fdx, fdy
  local FTYPE = types.array2d(types.uint(8),window*T,window)
  local DTYPE = types.array2d(dtype,window*T,window)
  local ITYPE = types.tuple{ FTYPE, FTYPE, DTYPE, DTYPE }
  local finp = R.input( R.Handshake(ITYPE) )
  local finp_brd = R.apply("finp_broadcast", RM.broadcastStream(ITYPE,4), finp)
  
  local frame0 = R.apply("frame0", RM.makeHandshake(C.index(ITYPE,0)), R.selectStream("i0",finp_brd,0))
  local frame0 = FIFO( fifos, statements, FTYPE, frame0)
  local frame1 = R.apply("frame1", RM.makeHandshake(C.index(ITYPE,1)), R.selectStream("i1",finp_brd,1))
  local frame1 = FIFO( fifos, statements, FTYPE, frame1)
  local Fdx = R.apply("fdx", RM.makeHandshake(C.index(ITYPE,2)), R.selectStream("i2",finp_brd,2))
  local Fdx = FIFO( fifos, statements, DTYPE, Fdx)
  local Fdy = R.apply("fdy", RM.makeHandshake(C.index(ITYPE,3)), R.selectStream("i3",finp_brd,3))
  local Fdy = FIFO( fifos, statements, DTYPE, Fdy)

  ---------
  local gmf = R.tuple("mfgmf",{frame1,frame0},false)
  gmf = R.apply("SA",C.SoAtoAoSHandshake(window*T, window, {types.uint(8),types.uint(8)}), gmf)
  local m, gmf_type, gmf_cost = minus(types.uint(8))
  --print("GMF type", gmf_type)
  cost = cost + gmf_cost*window*window
  gmf = R.apply("SSM",RM.makeHandshake(RM.map(m,window*T,window)), gmf)
  gmf = FIFO( fifos, statements, types.array2d(gmf_type,window*T,window), gmf)
  ---------

  local partial = makePartial( dtype, gmf_type, bits.Bpartial[1], bits.Bpartial[2] )
  bits.Bpartial[3] = partial[3]
  local partial_type = partial[2]
  --print("MakeB Partial Type",partial_type)
  local partialfn = partial[1]

  local rsumfn = makeSumReduce(partial_type,false)
  local rsumAsyncfn = makeSumReduce(partial_type,true)

  local out_0 = R.tuple("o0tup",{Fdx, gmf},false)
  local out_0 = R.apply("o0P", C.SoAtoAoSHandshake(window*T,window,{dtype, gmf_type}), out_0)
  local out_0 = R.apply("o0", RM.makeHandshake(RM.map(partialfn, window*T, window)), out_0)
  local out_0 = R.apply("out0red", RM.makeHandshake(RM.reduce(rsumfn, window*T, window)), out_0 )
  local out_0 = R.apply("out0redseq", RM.liftHandshake(RM.liftDecimate(RM.reduceSeq(rsumAsyncfn, T))), out_0 )

  local out_1 = R.tuple("o1tup",{Fdy, gmf},false)
  local out_1 = R.apply("o1P", C.SoAtoAoSHandshake(window*T,window,{dtype,gmf_type}), out_1)
  local out_1 = R.apply("o1", RM.makeHandshake(RM.map(partialfn, window*T, window)), out_1)
  local out_1 = R.apply("out1red", RM.makeHandshake(RM.reduce(rsumfn, window*T, window)), out_1 )
  local out_1 = R.apply("out1redseq", RM.liftHandshake(RM.liftDecimate(RM.reduceSeq(rsumAsyncfn, T))), out_1 )

  local out = R.tuple("arrrrry0t",{out_0,out_1},false)
  out = R.apply("PT",RM.packTuple({partial_type,partial_type}),out)
  out = R.apply("PTC",RM.makeHandshake(C.tupleToArray(partial_type,2)),out)

  table.insert(statements,1,out)

  --print("B output type", partial_type)
  return RM.lambda("b", finp, R.statements(statements),fifos), partial_type, cost
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
  return out:toDarkroom("solve"), out_0.type, out:cost()
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
  return out:toDarkroom("display"), out:cost()
end

function makeLK( internalT, internalW, internalH, window, bits )
  assert(type(window)=="number")
  assert(type(bits)=="table")

  local fifos = {}
  local statements = {}

  local cost = 9

  local INPTYPE = types.array2d(types.uint(8),2)
  local inp = R.input(R.Handshake(INPTYPE))
  local frame0 = R.apply("f0", RM.makeHandshake(C.index(INPTYPE, 0 )), inp)
  local frame1 = R.apply("f1", RM.makeHandshake(C.index(INPTYPE, 1 )), inp)


  local frame0_arr = R.apply("f0_arr", RM.makeHandshake(C.arrayop(types.uint(8),1)), frame0)
  local frame0_arr_brd = R.apply("f0_arr_broadcast", RM.broadcastStream(types.array2d(types.uint(8),1),2), frame0_arr)
--  local frame0_arr_brd = frame0_arr
  local frame1_arr = R.apply("f1_arr", RM.makeHandshake(C.arrayop(types.uint(8),1)), frame1)

  local st_sl_type = types.array2d( types.uint(8), window*internalT, window+1 )

  local lb0 = FIFO(fifos,statements,types.array2d(types.uint(8),1),R.selectStream("f0a",frame0_arr_brd,0))
  local lb0 = R.apply("lb0", C.stencilLinebufferPartialOffsetOverlap( types.uint(8), internalW, internalH, internalT, -window, 0, -window, 0, 1, 0 ), lb0)
  local lb0 = R.apply("lb0_slc", RM.makeHandshake(C.slice( st_sl_type, 0, window*internalT-1, 0, window-1)), lb0)

  local lb1 = FIFO(fifos,statements,types.array2d(types.uint(8),1),frame1_arr)
  local lb1 = R.apply("lb1", C.stencilLinebufferPartialOffsetOverlap(types.uint(8), internalW, internalH, internalT, -window, 0, -window, 0, 1, 0 ), lb1)
  local lb1 = R.apply("lb1_slc", RM.makeHandshake(C.slice( st_sl_type, 0, window*internalT-1, 0, window-1)), lb1)

  local lb0_fd = FIFO(fifos,statements,types.array2d(types.uint(8),1),R.selectStream("f0a1",frame0_arr_brd,1))
  local lb0_fd = R.apply("lb0_fd", RM.makeHandshake(C.stencilLinebuffer(types.uint(8), internalW, internalH, 1, -2, 0, -2, 0 )), lb0_fd)
  local lb0_fd_brd = R.apply("lb0_fd_brd", RM.broadcastStream(types.array2d(types.uint(8),3,3),2), lb0_fd)
  local lb0_fd_0 = FIFO(fifos,statements,types.array2d(types.uint(8),3,3),R.selectStream("ln0",lb0_fd_brd,0))
  local lb0_fd_1 = FIFO(fifos,statements,types.array2d(types.uint(8),3,3),R.selectStream("ln1",lb0_fd_brd,1))

  local st_type = types.array2d( types.uint(8), 3, 3 )

  local fdx = R.apply("slx", RM.makeHandshake(C.slice( st_type, 0, 2, 1, 1)), lb0_fd_0)
  local dx, dType, dxcost = dx(bits)
  local fdx = R.apply("fdx", RM.makeHandshake(dx), fdx)
  local fdx_arr = R.apply("fdx_arr", RM.makeHandshake(C.arrayop(dType,1)), fdx)
  local fdx_stencil = R.apply("fdx_stencil", C.stencilLinebufferPartial(dType, internalW, internalH, internalT, -window+1, 0, -window+1, 0 ), fdx_arr)
  local stDType = types.array2d(dType,window*internalT,window)
  local fdx_stencil = R.apply("fdxbrd", RM.broadcastStream(stDType,2), fdx_stencil)
  local fdx_stencil_0 = FIFO(fifos,statements,stDType,R.selectStream("fdxs0",fdx_stencil,0))
  local fdx_stencil_1 = FIFO(fifos,statements,stDType,R.selectStream("fdxs1",fdx_stencil,1))

  local fdy = R.apply("sly", RM.makeHandshake(C.slice( st_type, 1, 1, 0, 2)), lb0_fd_1)
  local fdy = R.apply("fdy", RM.makeHandshake(dy(bits)), fdy )
  local fdy_arr = R.apply("fdy_arr", RM.makeHandshake(C.arrayop(dType,1)), fdy)
  local fdy_stencil = R.apply("fdy_stencil", C.stencilLinebufferPartial(dType, internalW, internalH, internalT, -window+1, 0, -window+1, 0 ), fdy_arr)
  local fdy_stencil = R.apply("fdybrd", RM.broadcastStream(stDType,2), fdy_stencil)
  local fdy_stencil_0 = FIFO(fifos,statements,stDType,R.selectStream("fdys0",fdy_stencil,0))
  local fdy_stencil_1 = FIFO(fifos,statements,stDType,R.selectStream("fdys1",fdy_stencil,1))

  cost = cost + dxcost*2

  local Af, AType, Acost = makeA( internalT, dType, window, bits )

  local A = R.apply("APT",RM.packTuple{stDType,stDType},R.tuple("ainp",{fdx_stencil_0,fdy_stencil_0},false))
  local A = R.apply("A", Af, A)

  local fAinv, AInvType = invert2x2( AType, bits )
  local Ainv = R.apply("Ainv", RM.makeHandshake(fAinv), A)
  local Ainv = FIFO(fifos,statements,types.array2d(AInvType,4),Ainv)

  local fB, BType, Bcost = makeB( internalT, dType, window, bits )

  local smst = types.array2d(types.uint(8),window*internalT,window)
  local b = R.apply("bpt", RM.packTuple{smst,smst,stDType,stDType}, R.tuple("btup",{lb0,lb1,fdx_stencil_1,fdy_stencil_1},false) )
  local b = R.apply("b",fB, b)
  local b = FIFO(fifos,statements,types.array2d(BType,2),b)

  --print("ATYPE,BTYPE",AInvType,BType)
  local fSolve, SolveType, SolveCost = solve( AInvType, BType, bits )
  local vectorField = R.apply("VF", RM.packTuple{types.array2d(AInvType,4), types.array2d(BType,2)}, R.tuple("solveinp",{Ainv,b},false) )
  local vectorField = R.apply("solve", RM.makeHandshake(fSolve), vectorField)
  cost = cost + SolveCost

  local displayfn, displaycost = display(SolveType)
  local out = R.apply("display", RM.makeHandshake(displayfn), vectorField)
  cost = cost + displaycost

  table.insert(statements,1,out)
--out=fdx_dbg
  return RM.lambda("LK",inp,R.statements(statements),fifos), cost
end

function LKTop(internalT,W,H,window,bits)
  assert(type(bits)=="table")

  local internalW = W+window
  local internalH = H+window+1
  local PadRadius = window/2

  local ITYPE = types.array2d(types.uint(8),2)
  local T = 4
  
  local RW_TYPE = types.array2d( ITYPE, T ) -- simulate axi bus
  local hsfninp = R.input( R.Handshake(RW_TYPE) )
  local out = R.apply("reducerate", RM.liftHandshake(RM.changeRate(types.array2d(types.uint(8),2),1,4,1)), hsfninp )
  local out = R.apply("pad", RM.liftHandshake(RM.padSeq(ITYPE, W, H, 1, PadRadius, PadRadius, PadRadius+1, PadRadius, {0,0})), out)
  local out = R.apply("idx", RM.makeHandshake(C.index(types.array2d(types.array2d(types.uint(8),2),1),0)), out)
  local lkfn, lkcost = makeLK( internalT, internalW, internalH, window, bits )
  out = R.apply("LK", lkfn, out )
  local out = R.apply("pack", RM.makeHandshake(C.arrayop(types.array2d(types.uint(8),2),1)), out)
  local out = R.apply("crop",RM.liftHandshake(RM.liftDecimate(C.cropHelperSeq(ITYPE, internalW, internalH, 1, PadRadius*2, 0, PadRadius*2+1, 0))), out)
  local out = R.apply("incrate", RM.liftHandshake(RM.changeRate(ITYPE,1,1,4)), out )
  local hsfn = RM.lambda("hsfn", hsfninp, out)
  return hsfn, lkcost
end