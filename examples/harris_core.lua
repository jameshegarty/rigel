local R = require "rigel"
local RM = require "modules"
local f = require "fixed_float"
local types = require "types"
local C = require "examplescommon"
local J = require "common"

local G  = {14 , 62 , 104 , 62 , 14}

harris = {}

floatMult = J.memoize(function(Atype)
  local inp = f.parameter("fm",types.tuple{Atype,Atype})
  local A,B = inp:index(0), inp:index(1)
  if f.isFixedType(Atype)==false then
    A = A:lift(0)
    B = B:lift(0)
  end
  local out = A*B
  return {out:toRigelModule("floatMult_"..tostring(Atype):gsub('%W','_')), out.type}
                    end)

floatSum = J.memoize(function(A)
  assert(types.isType(A))
  local inp = f.parameter("fm",types.tuple{A,A})
  local out = (inp:index(0))+(inp:index(1))
  return {out:toRigelModule("floatSum"), out.type}
                   end)

floatShift = J.memoize(function(A,amount)
  assert(types.isType(A))
  assert(type(amount)=="number")
  local inp = f.parameter("fm",A)
  local out = inp:rshift(amount)
  return {out:toRigelModule("floatShift"), out.type}
                     end)

function convolveFloat( A, ConvWidth, ConvHeight, tab, shift, X )
  assert(type(ConvWidth)=="number")
  assert(type(ConvHeight)=="number")
  assert(type(tab)=="table")
  assert(type(shift)=="number")
  assert(X==nil)

  local inp = R.input( types.array2d( A, ConvWidth, ConvHeight ) )
  local r = R.constant( "convkernel", tab, types.array2d( A, ConvWidth, ConvHeight) )

  local packed = R.apply( "packedtup", C.SoAtoAoS(ConvWidth,ConvHeight,{A,A}), R.concat("ptup", {inp,r}) )
  local FM = floatMult(A)
  local conv = R.apply( "partial", RM.map( FM[1], ConvWidth, ConvHeight ), packed )
  local SM = floatSum(FM[2])
  local conv = R.apply( "sum", RM.reduce( SM[1], ConvWidth, ConvHeight ), conv )
  local Shift = floatShift(SM[2],shift)
  local conv = R.apply( "touint8", Shift[1], conv )

  local convolve = RM.lambda( "convolveConstant_W"..tostring(ConvWidth).."_H"..tostring(ConvHeight), inp, conv )
  return convolve, Shift[2]
end

function harris.makeHarrisKernel(dxType, dyType)
  local K = 0.00000001

  --print("HARRISTYPE",dxType)
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
  local res = out:toRigelModule("harrisinner")
  return res, out.type
end


function harris.makeNMS(ty, boolOutput, X)
  assert(types.isType(ty))
  assert(type(boolOutput)=="boolean")
  assert(X==nil)

  local THRESH = 0.001

  local inp = f.parameter("nmsinp", types.array2d(ty,3,3))
  local N = (inp:index(1,1)):gt(inp:index(1,0))
  local S = (inp:index(1,1)):ge(inp:index(1,2))
  local E = (inp:index(1,1)):gt(inp:index(2,1))
  local W = (inp:index(1,1)):ge(inp:index(0,1))
  local nms = N:__and(S)
  nms = nms:__and(E)
  nms = nms:__and(W)
  local out = nms:__and((inp:index(1,1)):gt(f.constant(THRESH)))
  if boolOutput==false then
    out = f.select(out,f.plainconstant(255,types.uint(8)),f.plainconstant(0,types.uint(8)))
  end
  return out:toRigelModule("nms")
end

function harris.makeDXDYKernel(ty)
  --print("DXDYINP",ty)
  local inp = f.parameter("dx",types.array2d(ty,3,3))

  local dx = (inp:index(2,1))-(inp:index(0,1))
  dx = dx:rshift(1)

  local dy = (inp:index(1,2))-(inp:index(1,0))
  dy = dy:rshift(1)

--  local out = dy:lower(types.uint(8))
--  return out:toRigelModule("DXDY"), types.uint(8)

  local out = f.tuple{dx,dy}
--  print("DXDYTYPE",out.type,dx.type)
  return out:toRigelModule("DXDY"), dx.type
end

function harris.makeDXDY(W,H,X)
  assert(type(W)=="number")
  assert(type(H)=="number")
  assert(X==nil)

  local T = 1
  local A = types.uint(8)
  local inp = R.input(R.Handshake(types.array2d(types.uint(8),T)))

  local blurXFn, blurXType = convolveFloat(types.uint(8),5,1,G,8)
  local blurX = R.apply("blurX",C.stencilKernelPadcrop(A,W,H,T,2,2,0,0,0,blurXFn),inp)

  local blurYFn = convolveFloat(blurXType,1,5,G,8)
  local blurXY = R.apply("blurXY",C.stencilKernelPadcrop(blurXType,W,H,T,0,0,2,2,0,blurYFn),blurX)

  local dxdyFn, dxdyType = harris.makeDXDYKernel(blurXType)
  local dxdySt = C.stencilKernelPadcrop(blurXType,W,H,T,1,1,1,1,0,dxdyFn)
  local dxdy = R.apply("dxdy", dxdySt, blurXY )

  return RM.lambda("dxdytop", inp, dxdy), dxdyType
end

-- W,H are image W,H
function harris.makeHarris(W,H,boolOutput,X)
  assert(type(W)=="number")
  assert(type(H)=="number")
  assert(type(boolOutput)=="boolean")
  assert(X==nil)

  local T = 1
  local inp = R.input(R.Handshake(types.array2d(types.uint(8),T)))

  local dxdyfn, dxdyType = harris.makeDXDY(W,H)
  local dxdy = R.apply("dxdy",dxdyfn,inp)
  local dxdy = R.apply("dxidx",RM.makeHandshake(C.index(types.array2d(types.tuple{dxdyType,dxdyType},1),0,0)),dxdy)

  local harrisFn, harrisType = harris.makeHarrisKernel(dxdyType,dxdyType)
  local out = R.apply("harris", RM.makeHandshake(harrisFn), dxdy)
  out = R.apply("AO",RM.makeHandshake(C.arrayop(harrisType,1,1)),out)

  local nmsFn = harris.makeNMS( harrisType, boolOutput )
  local nms = R.apply("nms", C.stencilKernelPadcrop(harrisType,W,H,T,1,1,1,1,0,nmsFn), out)

  return RM.lambda("Harristop", inp, nms)
end

function harris.harrisWithStencil(t)
  local inp = R.input( R.Handshake(types.array2d(types.uint(8),1) ))

  local fifos = {}
  local statements = {}

  ---------------------
  -- Make DXDY
  local dxdyFn, dxdyType = harris.makeDXDY(t.W,t.H)
  local DXDY_PAIR = types.tuple{dxdyType,dxdyType}
  --print("DXDY",DXDY_PAIR)
--  local out = R.apply("ARR",RM.makeHandshake(C.arrayop(types.uint(8),1)), inp)
  local out = R.apply("dxdy",dxdyFn, inp)

  out = R.apply("pad", RM.liftHandshake(RM.padSeq(DXDY_PAIR, t.W, t.H, 1, 7, 8, 7, 8, {0,0})), out)

  out = R.apply("dxdyix",RM.makeHandshake(C.index(types.array2d(DXDY_PAIR,1,1),0,0)),out)

  local dxdyBroad = R.apply("dxdy_broad", RM.broadcastStream(DXDY_PAIR,2), out)

  local internalW = t.W+15
  local internalH = t.H+15

  -------------------------------
  -- right branch: make the harris bool
  local right = R.selectStream("d1",dxdyBroad,1)
  right = C.fifoLoop( fifos, statements, DXDY_PAIR, right, 128, "rightFIFO")

  local harrisFn, harrisType = harris.makeHarrisKernel(dxdyType,dxdyType)
  local right = R.apply("harris", RM.makeHandshake(harrisFn), right)
  local right = R.apply("AO",RM.makeHandshake(C.arrayop(harrisType,1,1)), right)

  -- now stencilify the harris
  local right = R.apply( "harris_st", RM.makeHandshake(C.stencilLinebuffer(harrisType, internalW, internalH, 1,-2,0,-2,0)), right)
  local nmsFn = harris.makeNMS( harrisType, true )
  local right = R.apply("nms", RM.makeHandshake(nmsFn), right)

  -------------------------------
  -- left branch: make the dxdy int8 stencils
  local left = R.selectStream("d0",dxdyBroad,0)

  if GRAD_INT then
    --print("GRAD_INT=true")
    left = R.apply("lower", RM.makeHandshake(sift.lowerPair(dxdyType,GRAD_TYPE,GRAD_SCALE)), left)
    dxdyType = GRAD_TYPE
    DXDY_PAIR = types.tuple{GRAD_TYPE,GRAD_TYPE}
  else
    --print("GRAD_INT=false")
  end
  
  left = C.fifoLoop( fifos, statements, DXDY_PAIR, left, 2048/DXDY_PAIR:verilogBits(), "leftFIFO")

  local left = R.apply("stlbinp", RM.makeHandshake(C.arrayop(DXDY_PAIR,1,1)), left)
  local left = R.apply( "stlb", RM.makeHandshake(C.stencilLinebuffer(DXDY_PAIR, internalW, internalH, 1,-TILES_X*4+1,0,-TILES_Y*4+1,0)), left)
  left = R.apply("stpos", RM.makeHandshake(sift.addPos(dxdyType,internalW,internalH,15,15)), left)
  -------------------------------
  -- merge left/right

  local FILTER_TYPE = types.tuple{types.array2d(DXDY_PAIR,TILES_X*4,TILES_Y*4),types.tuple{types.uint(16),types.uint(16)}}
  local FILTER_PAIR = types.tuple{FILTER_TYPE,types.bool()}

  local out = R.apply("merge",RM.packTuple{FILTER_TYPE,types.bool()},R.concat("MPT",{left,right}))

  local out = R.apply("cropao", RM.makeHandshake(C.arrayop(FILTER_PAIR,1,1)), out)
  local out = R.apply("crp", RM.liftHandshake(RM.liftDecimate(RM.cropSeq(FILTER_PAIR,t.W+15,t.H+15,1,15,0,15,0))), out)
  local out = R.apply("crpidx", RM.makeHandshake(C.index(types.array2d(FILTER_PAIR,1,1),0,0)), out)

  table.insert( statements, 1, out)

  return RM.lambda("harrisWithStencil", inp, R.statements(statements), fifos)
end

return harris
