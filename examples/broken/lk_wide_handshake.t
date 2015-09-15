local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"
local f = require "fixed"

W = 128
H = 128
--T = 8

-- lk_full is 584x388, 2 channel

local window = 8

function invtable(exp)
  local out = {}
  local terra inv(a:uint32) 
    if a==0 then 
      return 0 
    else
      var o = [math.pow(2,exp)]/a
      if o>255 then return 255 end
      return o
    end 
  end

  for i=0,255 do table.insert(out, inv(i)) end
  return out
end

-- note that we use our convetion here:
-- index 0,0 is bottom left of matrix. index 1,1 is top right
-- Atype: type of entries of A matrix
function invert2x2( AType )
  f.expectFixed(AType)
  local inp = d.input( types.array2d(AType,4) )

  --------
  local finp = f.parameter( "finp", types.array2d(AType,4) )
  local fdenom = finp:index(0)*finp:index(3)-finp:index(1)*finp:index(2)
  fdenom = fdenom:hist("denom"):truncate(8)
  local signbit = fdenom:sign()
  local fdenom = fdenom:abs() -- fdenom now uint8.e
  print("denom prec", fdenom:precision())
  local denom_exp = fdenom:exp()
  print("denom exp", denom_exp)
  local fdenom = fdenom:lower(true) -- fdenom is now uint8
  local fdenom = f.tuple{fdenom,signbit}
  fdenom = fdenom:toDarkroom("denom")
  --------

  local lut_exp = -10
  local denom = d.apply("denom", fdenom, inp)
  local denom_denom = d.apply("denom_denom", d.index(fdenom.outputType,0), denom)
  local denom_signbit = d.apply("denom_signbit", d.index(fdenom.outputType,1), denom)
  local det = d.apply("det", d.lut(types.uint(8), types.uint(8), invtable(-lut_exp)), denom_denom)

  ---------
  local finp = f.parameter( "finpt", types.tuple{types.array2d(AType,4), types.uint(8), types.bool()} )
  local fmatrix = finp:index(0)
  local fsignbit = finp:index(2)
  local fdet = finp:index(1):lift(denom_exp+lut_exp):addSign(fsignbit)
  local I0 = fdet*fmatrix:index(3)
  local output_type = I0.type
  local fout = f.array2d({I0, fdet:neg()*fmatrix:index(1), fdet:neg()*fmatrix:index(2), fdet*fmatrix:index(0)},4)
  ---------

  local out = d.apply("out", fout:toDarkroom("fout"), d.tuple("ftupp",{inp,det, denom_signbit}))

  print("invert2x2 output type:", output_type)
  return d.lambda("invert2x2", inp, out ), output_type
end

function dx()
  local inp = f.parameter("dxinp", types.array2d(types.uint(8),3,1))
  local out = (inp:index(2):lift(0):toSigned() - inp:index(0):lift(0):toSigned()):rshift(1)
  return out:toDarkroom("dx"), out.type
end

function dy()
  local inp = f.parameter("dyinp", types.array2d(types.uint(8),1,3))
  return (inp:index(0,2):lift(0):toSigned() - inp:index(0,0):lift(0):toSigned()):rshift(1):toDarkroom("dy")
end

function makePartial(ltype,rtype)
  f.expectFixed(ltype)
  f.expectFixed(rtype)
  local finp = f.parameter("pi",types.tuple{ltype,rtype})
  local out = finp:index(0)*finp:index(1)
  return out:toDarkroom("partial_"..tostring(ltype)..tostring(rtype)), out.type
end

function makeSumReduce(inputType)
  local finp = f.parameter("pi",types.tuple{inputType,inputType})
  return (finp:index(0)+finp:index(1)):cast(inputType):toDarkroom("rsum")
end

-- dType: type of derivative
function makeA( dType )
  f.expectFixed( dType )
  local stt = types.array2d(dType, window, window)
  local inpt = types.tuple{ stt, stt }
  local inp = d.input( inpt )
  local Fdx = d.apply("fdx", d.index(inpt,0), inp)
  local Fdy = d.apply("fdy", d.index(inpt,1), inp)

  local partial, partial_type = makePartial( dType, dType )
  print("A partial type", partial_type)
  local rsum = makeSumReduce(partial_type)

  local inp0 = d.apply("inp0", d.SoAtoAoS(window,window,{dType,dType}), d.tuple("o0",{Fdx,Fdx}) )
  local out0 = d.apply("out0", d.map(partial, window, window), inp0 )

  local inp1 = d.apply("inp1", d.SoAtoAoS(window,window,{dType,dType}), d.tuple("o1",{Fdx,Fdy}) )
  local out1 = d.apply("out1", d.map(partial, window, window), inp1 )
  local out2 = out1

  local inp3 = d.apply("inp3", d.SoAtoAoS(window,window,{dType,dType}), d.tuple("o3",{Fdy,Fdy}) )
  local out3 = d.apply("out3", d.map(partial, window, window), inp3 )

  local out = d.array2d("out", {out0,out1,out2,out3}, 4 )

  return d.lambda("A", inp, out ), partial_type
end

function minus(ty)
  assert(types.isType(ty))
  local inp = f.parameter("minux_inp",types.tuple{ty,ty})
  local out = inp:index(0):lift(0):toSigned()-inp:index(1):lift(0):toSigned()
  return out:toDarkroom("minus"), out.type
end

function makeB(dtype)
  f.expectFixed(dtype)

  -- arguments: frame1, frame2, fdx, fdy
  local FTYPE = types.array2d(types.uint(8),window)
  local DTYPE = types.array2d(dtype,window)
  local ITYPE = types.tuple{ FTYPE, FTYPE, DTYPE, DTYPE }
  local finp = d.input( ITYPE )
  
  local frame0 = d.apply("frame0", d.index(ITYPE,0), finp)
  local frame1 = d.apply("frame1", d.index(ITYPE,1), finp)
  local Fdx = d.apply("fdx", d.index(ITYPE,2), finp)
  local Fdy = d.apply("fdy", d.index(ITYPE,3), finp)

  ---------
  local gmf = d.tuple("mfgmf",{frame0,frame1})
  gmf = d.apply("SA",d.SoAtoAoS(window, window, {types.uint(8),types.uint(8)}), gmf)
  local m, gmf_type = minus(types.uint(8))
  gmf = d.apply("SSM",d.map(m,window,window), gmf)
  ---------

  local partial, partial_type = makePartial( dtype, gmf_type)

  local out_0 = d.tuple("o0tup",{Fdx, gmf})
  local out_0 = d.apply("o0P", d.SoAtoAoS(window,window,{dtype,gmf_type}), out_0)
  local out_0 = d.apply("o0", d.map(partial, window, window), out_0)

  local out_1 = d.tuple("o1tup",{Fdy, gmf})
  local out_1 = d.apply("o1P", d.SoAtoAoS(window,window,{dtype,gmf_type}), out_1)
  local out_1 = d.apply("o1", d.map(partial, window, window), out_1)

  local out = d.array2d("arrrrry0t",{out_0,out_1},2)

  print("B output type", partial_type)
  return d.lambda("b", finp, out), partial_type
end

function solve(AinvType, btype)
  assert( types.isType(AinvType) )
  assert( types.isType(btype) )

  local inp = f.parameter( "solveinp", types.tuple{types.array2d(AinvType,4), types.array2d(btype,2)} )
  local Ainv = inp:index(0)
  local b = inp:index(1)
  local out_0 = Ainv:index(0)*b:index(0):neg() + Ainv:index(1)*b:index(1):neg()
  local out_1 = Ainv:index(2)*b:index(0):neg() + Ainv:index(3)*b:index(1):neg()
  local out = f.array2d({out_0,out_1},2)
  print("Solve Output Type", out_0.type)
  return out:toDarkroom("solve"), out_0.type
end

function display(inpType)
  f.expectFixed(inpType)

  local inp = f.parameter("displayinp",types.array2d(inpType,2))
  local out = {}
  for i=0,1 do
    local I = inp:index(i)
    local B = I*f.constant(32,true,6,0)
    table.insert(out, (B+f.constant(128,true,8,0):cast(B.type)):denormalize():truncate(8):lower())
  end
  table.insert(out, f.constant(0,true,8,0):lower())
  out = f.array2d(out,3)
  return out:toDarkroom("display")
end

function makeLK()
  local INPTYPE = types.array2d(types.uint(8),2)
  local inp = d.input(INPTYPE)
  local frame0 = d.apply("f0", d.index(INPTYPE, 0 ), inp)
  local frame1 = d.apply("f1", d.index(INPTYPE, 1 ), inp)

  local st_type = types.array2d( types.uint(8), window+1, window+1 )
  local lb0 = d.apply("lb0", d.stencilLinebuffer(types.uint(8), W,H, 1, -window-1, 0, -window-1, 0 ), frame0)
  local lb1 = d.apply("lb1", d.stencilLinebuffer(types.uint(8), W,H, 1, -window-1, 0, -window-1, 0 ), frame1)

  local fdx = d.apply("slx", d.slice( st_type, window-2, window, window-1, window-1), lb0)
  local dx, dType = dx()
  local fdx = d.apply("fdx", dx, fdx)

  local fdy = d.apply("sly", d.slice( st_type, window-1, window-1, window-2, window), lb0)
  local fdy = d.apply("fdy", dy(), fdy )

  local Af, AType = makeA(dType)
  local A = d.apply("A", Af, d.tuple("ainp",{fdx,fdy}))
  local fAinv, AInvType = invert2x2(AType)
  local Ainv = d.apply("Ainv", fAinv, A)

  local fB, BType = makeB(dType)
  local b = d.apply("b",fB, d.tuple("btup",{frame0,frame1,fdx,fdy}))
  local fSolve, SolveType = solve(AInvType,BType)
  local vectorField = d.apply("solve", fSolve, d.tuple("solveinp",{Ainv,b}))
  
  local out = d.apply("display", display(SolveType), vectorField)

  return d.lambda("LK",inp,out)
end

local RW_TYPE = types.array2d( types.array2d(types.uint(8),2), 4 ) -- simulate axi bus
local hsfninp = d.input( d.StatefulHandshake(RW_TYPE) )
local out = d.apply("reducerate", d.liftHandshake(d.changeRate(types.array2d(types.uint(8),2),1,4,1)), hsfninp )
out = d.apply("LK", d.makeHandshake(makeLK()), out )
local out = d.apply("incrate", d.liftHandshake(d.changeRate(types.array2d(types.uint(8),2),1,1,4)), out )
local hsfn = d.lambda("hsfn", hsfninp, out)

harness.axi( "pointwise_wide_handshake", hsfn, "lk_128.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W,H)