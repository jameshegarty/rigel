local d = require "darkroom"
local f = require "fixed_float"
local C = require "examplescommon"

local G  = {14 , 62 , 104 , 62 , 14}

floatMult = memoize(function(Atype)
  local inp = f.parameter("fm",types.tuple{Atype,Atype})
  local A,B = inp:index(0), inp:index(1)
  if f.isFixedType(Atype)==false then
    A = A:lift(0)
    B = B:lift(0)
  end
  local out = A*B
  return {out:toDarkroom("floatMult_"..tostring(Atype):gsub('%W','_')), out.type}
                    end)

floatSum = memoize(function(A)
  assert(types.isType(A))
  local inp = f.parameter("fm",types.tuple{A,A})
  local out = (inp:index(0))+(inp:index(1))
  return {out:toDarkroom("floatSum"), out.type}
                   end)

floatShift = memoize(function(A,amount)
  assert(types.isType(A))
  assert(type(amount)=="number")
  local inp = f.parameter("fm",A)
  local out = inp:rshift(amount)
  return {out:toDarkroom("floatShift"), out.type}
                     end)

function convolveFloat( A, ConvWidth, ConvHeight, tab, shift, X )
  assert(type(ConvWidth)=="number")
  assert(type(ConvHeight)=="number")
  assert(type(tab)=="table")
  assert(type(shift)=="number")
  assert(X==nil)

  local inp = d.input( types.array2d( A, ConvWidth, ConvHeight ) )
  local r = d.constant( "convkernel", tab, types.array2d( A, ConvWidth, ConvHeight) )

  local packed = d.apply( "packedtup", d.SoAtoAoS(ConvWidth,ConvHeight,{A,A}), d.tuple("ptup", {inp,r}) )
  local FM = floatMult(A)
  local conv = d.apply( "partial", d.map( FM[1], ConvWidth, ConvHeight ), packed )
  local SM = floatSum(FM[2])
  local conv = d.apply( "sum", d.reduce( SM[1], ConvWidth, ConvHeight ), conv )
  local Shift = floatShift(SM[2],shift)
  local conv = d.apply( "touint8", Shift[1], conv )

  local convolve = d.lambda( "convolveConstant_W"..tostring(ConvWidth).."_H"..tostring(ConvHeight), inp, conv )
  return convolve, Shift[2]
end

local function makeHarris(dxType, dyType)
  local K = 0.00000001

  print("HARRISTYPE",dxType)
  local inp = f.parameter("harrisinp",types.tuple{dxType,dyType})
  local inpdx = inp:index(0)
  local inpdy = inp:index(1)
  local Ixx = inpdx*inpdx
  local Ixy = inpdx*inpdy
  local Iyy = inpdy*inpdy
  local det = (Ixx*Iyy) - (Ixy*Ixy)
  local tr = Ixx+Iyy
  local trsq = tr*tr
  local out = det - (f.constant(K))*trsq
--  out = out:lshift(10):lower(types.uint(8))
  local res = out:toDarkroom("harrisinner")
  return res, out.type
end


local function makeNMS(ty)
  local THRESH = 0.001

  local inp = f.parameter("nmsinp", types.array2d(ty,3,3))
  local N = (inp:index(1,1)):gt(inp:index(1,0))
  local S = (inp:index(1,1)):ge(inp:index(1,2))
  local E = (inp:index(1,1)):gt(inp:index(2,1))
  local W = (inp:index(1,1)):ge(inp:index(0,1))
  local nms = N:__and(S)
  nms = nms:__and(E)
  nms = nms:__and(W)
  nms = nms:__and((inp:index(1,1)):gt(f.constant(THRESH)))
  local out = f.select(nms,f.plainconstant(255,types.uint(8)),f.plainconstant(0,types.uint(8)))
  return out:toDarkroom("nms")
end

local function makeDXDY(ty)
  print("DXDYINP",ty)
  local inp = f.parameter("dx",types.array2d(ty,3,3))

  local dx = (inp:index(2,1))-(inp:index(0,1))
  dx = dx:rshift(1)

  local dy = (inp:index(1,2))-(inp:index(1,0))
  dy = dy:rshift(1)

--  local out = dy:lower(types.uint(8))
--  return out:toDarkroom("DXDY"), types.uint(8)

  local out = f.tuple{dx,dy}
--  print("DXDYTYPE",out.type,dx.type)
  return out:toDarkroom("DXDY"), dx.type
end


-- W,H are image W,H
local function harris(W,H)
  local T = 1
  local A = types.uint(8)
  local inp = d.input(d.Handshake(types.array2d(types.uint(8),T)))

  local blurXFn, blurXType = convolveFloat(types.uint(8),5,1,G,8)
  local blurX = d.apply("blurX",C.stencilKernelPadcrop(A,W,H,T,2,2,0,0,0,blurXFn),inp)

  local blurYFn = convolveFloat(blurXType,1,5,G,8)
  local blurXY = d.apply("blurXY",C.stencilKernelPadcrop(blurXType,W,H,T,0,0,2,2,0,blurYFn),blurX)

  local dxdyFn, dxdyType = makeDXDY(blurXType)
  local dxdySt = C.stencilKernelPadcrop(blurXType,W,H,T,1,1,1,1,0,dxdyFn)
  local dxdy = d.apply("dxdy", dxdySt, blurXY )

  local dxdy = d.apply("dxidx",d.makeHandshake(d.index(types.array2d(types.tuple{dxdyType,dxdyType},1),0,0)),dxdy)

  local harrisFn, harrisType = makeHarris(dxdyType,dxdyType)
  local harris = d.apply("harris", d.makeHandshake(harrisFn), dxdy)
  harris = d.apply("AO",d.makeHandshake(C.arrayop(harrisType,1,1)),harris)

  local nmsFn = makeNMS(harrisType)
  local nms = d.apply("nms", C.stencilKernelPadcrop(harrisType,W,H,T,1,1,1,1,0,nmsFn), harris)

  return d.lambda("Harristop", inp, nms)
end

return harris