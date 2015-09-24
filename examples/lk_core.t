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
  local inp = d.input( types.array2d(AType,4) )
  local out, output_type
  local cost = 0

  if f.FLOAT then
    local finp = f.parameter( "finp", types.array2d(AType,4) )
    local fdenom = (finp:index(0)*finp:index(3))-(finp:index(1)*finp:index(2))
    local fdet = fdenom:invert()
    local fout = f.array2d({fdet*finp:index(3), (fdet:neg())*(finp:index(1)), (fdet:neg())*(finp:index(2)), fdet*finp:index(0)},4)
    out = d.apply("out", fout:toDarkroom("fout"), inp)
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
    
    local denom = d.apply("denom", fdenom, inp)
    local fdetfn, fdet_type = C.lutinvert(fdenom_type)
    local det = d.apply("det", fdetfn, denom)
    
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
    out = d.apply("out", fout:toDarkroom("fout"), d.tuple("ftupp",{inp,det}))
  end

  print("invert2x2 output type:", output_type)
  return d.lambda("invert2x2", inp, out ), output_type, cost
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
  print("OUT:COST",out:cost())
  return {out:toDarkroom("partial_"..tostring(ltype)..tostring(rtype)), out.type, prec, out:cost()}
                      end)

makeSumReduce = memoize(function(inputType)
                          assert(types.isType(inputType))
  print("MakeReduceSum",inputType)
  local finp = f.parameter("pi",types.tuple{inputType,inputType})
  local inp0 = finp:index(0)
  local O = (inp0+finp:index(1)):truncate(inp0:precision())
  return {O:toDarkroom("rsum_"..tostring(inputType)),O:cost()}
                        end)

-- dType: type of derivative
function makeA( dType, window, bits )
  f.expectFixed( dType )
  assert(type(bits)=="table")

  assert(type(window)=="number")

  local cost = 0

  local stt = types.array2d(dType, window, window)
  local inpt = types.tuple{ stt, stt }
  local inp = d.input( inpt )
  local Fdx = d.apply("fdx", d.index(inpt,0), inp)
  local Fdy = d.apply("fdy", d.index(inpt,1), inp)

  local partial = makePartial( dType, dType, bits.Apartial[1], bits.Apartial[2] )
  bits.Apartial[3] = partial[3]
  local partial_type=partial[2]
  local partialfn = partial[1]
  print("A partial type", partial_type, partial[4])
  cost = cost + partial[4]*3*window*window
  local rsum = makeSumReduce(partial_type)
  cost = cost + rsum[2]*3*window*window
  local rsumfn = rsum[1]

  local inp0 = d.apply("inp0", d.SoAtoAoS(window,window,{dType,dType}), d.tuple("o0",{Fdx,Fdx}) )
  local out0 = d.apply("out0", d.map(partialfn, window, window), inp0 )
  local out0 = d.apply("out0red", d.reduce(rsumfn, window, window), out0 )

  local inp1 = d.apply("inp1", d.SoAtoAoS(window,window,{dType,dType}), d.tuple("o1",{Fdx,Fdy}) )
  local out1 = d.apply("out1", d.map(partialfn, window, window), inp1 )
  local out1 = d.apply("out1red", d.reduce(rsumfn, window, window), out1 )

  local out2 = out1

  local inp3 = d.apply("inp3", d.SoAtoAoS(window,window,{dType,dType}), d.tuple("o3",{Fdy,Fdy}) )
  local out3 = d.apply("out3", d.map(partialfn, window, window), inp3 )
  local out3 = d.apply("out3red", d.reduce(rsumfn, window, window), out3 )

  local out = d.array2d("out", {out0,out1,out2,out3}, 4 )

  return d.lambda("A", inp, out ), partial_type, cost
end

function minus(ty)
  assert(types.isType(ty))
  local inp = f.parameter("minux_inp",types.tuple{ty,ty})
  local out = inp:index(0):lift(0):toSigned()-inp:index(1):lift(0):toSigned()
  return out:toDarkroom("minus"), out.type, out:cost()
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
  local finp = d.input( ITYPE )
  
  local frame0 = d.apply("frame0", d.index(ITYPE,0), finp)
  local frame1 = d.apply("frame1", d.index(ITYPE,1), finp)
  local Fdx = d.apply("fdx", d.index(ITYPE,2), finp)
  local Fdy = d.apply("fdy", d.index(ITYPE,3), finp)

  ---------
  local gmf = d.tuple("mfgmf",{frame1,frame0})
  gmf = d.apply("SA",d.SoAtoAoS(window, window, {types.uint(8),types.uint(8)}), gmf)
  local m, gmf_type, gmf_cost = minus(types.uint(8))
  print("GMF type", gmf_type)
  cost = cost + gmf_cost*window*window
  gmf = d.apply("SSM",d.map(m,window,window), gmf)
  ---------

  local partial = makePartial( dtype, gmf_type, bits.Bpartial[1], bits.Bpartial[2] )
  bits.Bpartial[3] = partial[3]
  local partial_type = partial[2]
  print("MakeB Partial Type",partial_type)
  local partialfn = partial[1]
  cost = cost + partial[4]*2*window*window
  local rsum = makeSumReduce(partial_type)
  local rsumfn = rsum[1]
  cost = cost + rsum[2]*2*window*window

  local out_0 = d.tuple("o0tup",{Fdx, gmf})
  local out_0 = d.apply("o0P", d.SoAtoAoS(window,window,{dtype, gmf_type}), out_0)
  local out_0 = d.apply("o0", d.map(partialfn, window, window), out_0)
  local out_0 = d.apply("out0red", d.reduce(rsumfn, window, window), out_0 )

  local out_1 = d.tuple("o1tup",{Fdy, gmf})
  local out_1 = d.apply("o1P", d.SoAtoAoS(window,window,{dtype,gmf_type}), out_1)
  local out_1 = d.apply("o1", d.map(partialfn, window, window), out_1)
  local out_1 = d.apply("out1red", d.reduce(rsumfn, window, window), out_1 )

  local out = d.array2d("arrrrry0t",{out_0,out_1},2)

  print("B output type", partial_type)
  return d.lambda("b", finp, out), partial_type, cost
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
  print("Solve Output Type", out_0.type,out.type,Ainv.type)
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
    print("FFDEN TYPE",FF_den.type)
    local FF_trunc = FF_den:truncate(8)
    print("FF_trunc", FF_trunc.type)
    table.insert(out, FF_trunc:lower(types.uint(8)))
  end
--  table.insert(out, f.constant(0,true,8,0):lower())
  out = f.array2d(out,2)
  return out:toDarkroom("display"), out:cost()
end

function makeLK( internalW, internalH, window, bits )
  assert(type(window)=="number")
  assert(type(bits)=="table")

  local cost = 9

  local INPTYPE = types.array2d(types.uint(8),2)
  local inp = d.input(INPTYPE)
  local frame0 = d.apply("f0", d.index(INPTYPE, 0 ), inp)
  local frame1 = d.apply("f1", d.index(INPTYPE, 1 ), inp)

  local st_type = types.array2d( types.uint(8), window+1, window+1 )
  local frame0_arr = d.apply("f0_arr", C.arrayop(types.uint(8),1), frame0)
  local frame1_arr = d.apply("f1_arr", C.arrayop(types.uint(8),1), frame1)
  local lb0 = d.apply("lb0", d.stencilLinebuffer(types.uint(8), internalW, internalH, 1, -window, 0, -window, 0 ), frame0_arr)
  local lb1 = d.apply("lb1", d.stencilLinebuffer(types.uint(8), internalW, internalH, 1, -window, 0, -window, 0 ), frame1_arr)

  local fdx = d.apply("slx", d.slice( st_type, window-2, window, window-1, window-1), lb0)
  local dx, dType, dxcost = dx(bits)
  local fdx = d.apply("fdx", dx, fdx)
  local fdx_arr = d.apply("fdx_arr", C.arrayop(dType,1), fdx)
  local fdx_stencil = d.apply("fdx_stencil", d.stencilLinebuffer(dType, internalW, internalH, 1, -window+1, 0, -window+1, 0 ), fdx_arr)

  local fdy = d.apply("sly", d.slice( st_type, window-1, window-1, window-2, window), lb0)
  local fdy = d.apply("fdy", dy(bits), fdy )
  local fdy_arr = d.apply("fdy_arr", C.arrayop(dType,1), fdy)
  local fdy_stencil = d.apply("fdy_stencil", d.stencilLinebuffer(dType, internalW, internalH, 1, -window+1, 0, -window+1, 0 ), fdy_arr)

  cost = cost + dxcost*2

  local Af, AType, Acost = makeA( dType, window, bits )
  local A = d.apply("A", Af, d.tuple("ainp",{fdx_stencil,fdy_stencil}))
  local fAinv, AInvType = invert2x2( AType, bits )
  local Ainv = d.apply("Ainv", fAinv, A)
  cost = cost + Acost

  local fB, BType, Bcost = makeB( dType, window, bits )
  local f0_slice = d.apply("f0slice", d.slice(st_type, 0, window-1, 0, window-1), lb0)
  local f1_slice = d.apply("f1slice", d.slice(st_type, 0, window-1, 0, window-1), lb1)
  local b = d.apply("b",fB, d.tuple("btup",{f0_slice,f1_slice,fdx_stencil,fdy_stencil}))
  cost = cost + Bcost

--  local A0 = d.apply("A0", d.index(fB.outputType,1),b)
--  local fdx_dbg = d.apply("fdx_dbg", toUint8Sign(BType), A0)

  local fSolve, SolveType, SolveCost = solve( AInvType, BType, bits )
  local vectorField = d.apply("solve", fSolve, d.tuple("solveinp",{Ainv,b}))
  cost = cost + SolveCost
  
  local displayfn, displaycost = display(SolveType)
  local out = d.apply("display", displayfn, vectorField)
  cost = cost + displaycost
--out=fdx_dbg
  return d.lambda("LK",inp,out), cost
end

function LKTop(W,H,window,bits)
  assert(type(bits)=="table")

  local internalW = W+window
  local internalH = H+window
  local PadRadius = window/2

  local ITYPE = types.array2d(types.uint(8),2)
  local T = 4
  
  local RW_TYPE = types.array2d( ITYPE, T ) -- simulate axi bus
  local hsfninp = d.input( d.Handshake(RW_TYPE) )
  local out = d.apply("reducerate", d.liftHandshake(d.changeRate(types.array2d(types.uint(8),2),1,4,1)), hsfninp )
  local out = d.apply("pad", d.liftHandshake(d.padSeq(ITYPE, W, H, 1, PadRadius, PadRadius, PadRadius, PadRadius, {0,0})), out)
  local out = d.apply("idx", d.makeHandshake(d.index(types.array2d(types.array2d(types.uint(8),2),1),0)), out)
  local lkfn, lkcost = makeLK( internalW, internalH, window, bits )
  out = d.apply("LK", d.makeHandshake( lkfn), out )
  local out = d.apply("pack", d.makeHandshake(C.arrayop(types.array2d(types.uint(8),2),1)), out)
  local out = d.apply("crop",d.liftHandshake(d.liftDecimate(d.cropHelperSeq(ITYPE, internalW, internalH, 1, PadRadius*2, 0, PadRadius*2, 0))), out)
  local out = d.apply("incrate", d.liftHandshake(d.changeRate(ITYPE,1,1,4)), out )
  local hsfn = d.lambda("hsfn", hsfninp, out)
  return hsfn, lkcost
end