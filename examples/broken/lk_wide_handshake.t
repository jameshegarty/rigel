local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"

W = 128
H = 64
T = 8

local stencilWidth = 8

function invtable(exp)
  local out = {}
  terra inv(a:uint32) 
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
function invert2x2(ty)
  local inp = d.input( types.array2d(ty,4) )

  --------
  local finp = f.input( types.array2d(ty,4) )
  local fdenom = finp:index(0)*finp:index(3)-finp:index(1)*finp:index(2)
  fdenom = fdenom:normalize(9)
  local fdenom, signbit = fdenom:abs() -- fdenom now uint8.e
  local fdenom, exp = fdenom:lower() -- fdenom is now uint8
  --------

  local denom = d.apply("denom", fdenom:toDarkroom(), inp)
  local det = d.apply("det", d.lut(types.uint(8), types.uint(8), invtable(exp)), denom)

  ---------
  local finp = f.input( types.tuple{types.array2d(ty,4), types.uint(8), types.bool()} )
  local fmatrix = finp:index(0)
  local fsigned = finp:index(2)
  local fdet = finp:index(1):toSigned(signbit)
  local fout = f.array2d({fdet*fmatrix:index(3), -fdet*fmatrix:index(1), -fdet*fmatrix:index(2), fdet*fmatrix(0)},2,2)
  ---------

  local out = d.apply("out", fout:toDarkroom(), d.tuple{inp,det, denom_signbit})

  return d.lambda("invert2x2", inp, out )
end

function dx()
  local inp = f.parameter("dxinp", types.array2d(types.uint(8),3,1))
  return f.rshift(inp:index(2):lift(0) - inp:index(0):lift(0),1):toDarkroom()
end

function dy()
  local inp = f.parameter("dyinp", types.array2d(types.uint(8),1,3))
  return f.rshift(inp:index(2):lift(0) - inp:index(0):lift(0),1):toDarkroom()
end

function makePartial(inputType)
  local finp = f.parameter("pi",types.tuple{inputType,inputType})
  return (finp:index(0)*finp:index(1)):toDarkroom()
end

function A(inputType)
  f.expectFixed(inputType)
  local stt = types.array2d(inputType, window, window)
  local inpt = types.tuple{ stt, stt }
  local inp = d.input("Ainp", inpt )
  local Fdx = d.apply("fdx",d.index(inpt,0), inp)
  local Fdy = d.apply("fdy",d.index(inpt,1), inp)

  local partial = makePartial(inputType)

  local inp0 = d.apply("inp0", d.SoAtoAoS(window,window,{inputType,inputType}), d.tuple("o0",{Fdx,Fdx})
  local out0 = d.apply("out0", d.map(partial, window, window), inp0 )

  local inp1 = d.apply("inp1", d.SoAtoAoS(window,window,{inputType,inputType}), d.tuple("o1",{Fdx,Fdy})
  local out1 = d.apply("out1", d.map(partial, window, window), inp1 )
  local out2 = out1

  local inp3 = d.apply("inp3", d.SoAtoAoS(window,window,{inputType,inputType}), d.tuple("o3",{Fdy,Fdy})
  local out3 = d.apply("out3", d.map(partial, window, window), inp3 )

  local out = d.array2d("out", {out0,out1,out2,out3}, 4 )

  return d.lambda("A", inp, out )
end

function minus(ty)
  local inp = f.input(types.tuple{ty,ty})
  local out = inp:index(0)-inp:index(1)
  return out:toDarkroom(), out.type
end

function b(dtype)
  -- arguments: frame1, frame2, fdx, fdy
  local finp = d.input( types.tuple{types.uint(8), types.uint(8), dtype, dtype} )
  
  ---------
  local gmf = d.tuple{d.index(finp,0), d.index(finp,1)}
  gmf = d.apply("SA",d.SoAtoAoS(window, window, {types,uint(8),types.uint(8)}), gmf)
  local m, gmf_type = minus(types.uint(8))
  gmf = d.apply("SSM",d.map(m),window,window), gmf)
  ---------

  local partial = makePartial(inputType)

  local out_0 = d.tuple{d.index(finp,2), gmf}
  local out_0 = d.apply("o0P", d.SoAtoAoS(window,window,{dtype,gmf_type}), out_0)
  local out_0 = d.apply("o0", d.map(partial, window, window), out_0)

  local out_1 = d.tuple{d.index(finp,3), gmf}
  local out_1 = d.apply("o1P", d.SoAtoAoS(window,window,{dtype,gmf_type}), out_1)
  local out_1 = d.apply("o1", d.map(partial, window, window), out_1)

  local out = d.array2d({out_0,out_1},2)
  return d.lambda("b", finp, out)
end

function solve(AinvType, btype)
  local inp = f.input( types.tuple{types.array2d(AinvType,4), types.array2d(btype,2)} )
  local Ainv = inp:index(0)
  local b = inp:index(1)
  local out_0 = Ainv:index(0)*f.neg(b:index(0)) + Ainv:index(1)*f.neg(b:index(1))
  local out_1 = Ainv:index(2)*f.neg(b:index(0)) + Ainv:index(3)*f.neg(b:index(1))
  local out = f.array2d({out_0,out_1},2)
  return out:toDarkroom()
end

function display(inpType)
  local inp = f.input(inpType)
  local out = {}
  for i=0,1 do
    table.insert(out, (inp:index(i)*f.constant(32)+f.constant(128)):denormalize():truncate(8))
  end
  table.insert(out, f.constant(0))
  out = f.array2d(out,3)
  return out:toDarkroom()
end

function makeLK()
  local inp = d.input(types.array2d(types.uint(8),2))
  local frame0 = d.index(inp,0)
  local frame1 = d.index(inp,1)

  local st_type = types.array2d(types.uint8,window+1,window+1)
  local lb0 = d.apply("lb0", d.stencilLinebuffer(types.uint(8), W,H, 1, -window-1, 0, -window-1, 0 ), frame0)
  local lb1 = d.apply("lb1", d.stencilLinebuffer(types.uint(8), W,H, 1, -window-1, 0, -window-1, 0 ), frame1)

  local fdx = d.apply("fdx", dx(), d.slice( lb0, st_type, window-2, window, window-1, window-1), lb0)
  local fdy = d.apply("fdy", dy(), d.slice( lb0, st_type, window-1, window-1, window-2, window), lb0)

  local A = d.apply("A", makeA(), d.tuple{fdx,fdy})
  local Ainv = d.apply("Ainv", invert2x2(), A)

  local b = d.apply("b",makeB(), d.tuple{frame0,frame1,fdx,fdy})
  local vectorField = d.apply("solve", solve(), d.tuple{Ainv,b})
  
  local out = d.apply("display", display(), vectorField)

  return d.lambda("LK",inp,out)
end

hsfn = d.makeHandshake(d.makeStateful(fn))

harness.axi( "pointwise_wide_handshake", hsfn, "frame_128.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W,H)