local R = require "rigel"
local rigel = R
local RM = require "modules"
local types = require "types"
local S = require "systolic"
local Ssugar = require "systolicsugar"
local modules = RM
local J = require "common"
local memoize = J.memoize
local err = J.err
local f = require "fixed_new"

if terralib~=nil then CT=require("examplescommonTerra") end

local C = {}

C.identity = memoize(function(A)
  local identity = RM.lift( "identity_"..J.verilogSanitize(tostring(A)), A, A, 0, function(sinp) return sinp end, function() return CT.identity(A) end, "C.identity")
  return identity
end)

C.cast = memoize(function(A,B)
  err(types.isType(A),"cast: A should be type")
  err(types.isType(B),"cast: B should be type")
  err( R.isBasic(A), "cast: A should be basic type. casting "..tostring(A).." to "..tostring(B) )
  err( R.isBasic(B), "cast: B should be basic type. casting "..tostring(A).." to "..tostring(B) )
  assert(A:isTuple()==false)
  local docast = RM.lift( J.sanitize("cast_"..tostring(A).."_"..tostring(B)), A, B, 0, function(sinp) return S.cast(sinp,B) end, function() return CT.cast(A,B) end, "C.cast" )
  return docast
end)

C.tupleToArray = memoize(function(A,N)
  err(types.isType(A),"tupleToArray: A should be type")
  err(type(N)=="number","tupleToArray: N must be number")

  local atup = types.tuple(J.broadcast(A,N))
  local B = types.array2d(A,N)

  local docast = RM.lift( J.sanitize("tupleToArray_"..tostring(A).."_"..tostring(N)), atup, B, 0,
    function(sinp) return S.cast(sinp,B) end,
    function() return CT.tupleToArray(A,N,atup,B) end, "C.tupleToArray")

  return docast
end)

------------
-- return A*B as a darkroom FN. A,B are types
-- returns something of type outputType
C.multiply = memoize(function(A,B,outputType)
  err( types.isType(A), "C.multiply: A must be type")
  err( types.isType(B), "C.multiply: B must be type")
  err( types.isType(outputType), "C.multiply: outputType must be type")

  local partial = RM.lift( J.sanitize("mult_A"..tostring(A).."_B"..tostring(B).."_"..tostring(outputType)), types.tuple {A,B}, outputType, 1,
    function(sinp) return S.cast(S.index(sinp,0),outputType)*S.cast(S.index(sinp,1),outputType) end,
    function() return CT.multiply(A,B,outputType) end,
    "C.multiply" )

  return partial
end)

------------
-- return A+B as a darkroom FN. A,B are types
-- returns something of type outputType
C.sum = memoize(function( A, B, outputType, async )
  err( types.isType(A), "C.sum: A must be type")
  err( types.isType(B), "C.sum: B must be type")
  err( types.isType(outputType), "C.sum: outputType must be type")

  if async==nil then return C.sum(A,B,outputType,false) end

  err(type(async)=="boolean","C.sum: async must be boolean")

  local delay
  if async then delay = 0 else delay = 1 end

  local partial = RM.lift(
    J.sanitize("sum_"..tostring(A)..tostring(B)..tostring(outputType).."_async_"..tostring(async)), types.tuple {A,B}, outputType, delay,
    function(sinp)
      local sout = S.cast(S.index(sinp,0),outputType)+S.cast(S.index(sinp,1),outputType)
      if async then sout = sout:disablePipelining() end
      return sout
    end,
    function()
      return CT.sum(A,B,outputType,async)
    end,
    "C.sum")

  return partial
end)

------------
-- return A-B as a darkroom FN. A,B are types
-- returns something of type outputType
C.sub = memoize(function( A, B, outputType, async )
  err( types.isType(A), "C.sub: A must be type")
  err( types.isType(B), "C.sub: B must be type")
  err( types.isType(outputType), "C.sub: outputType must be type")

  if async==nil then return C.sub(A,B,outputType,false) end

  local delay
  if async then delay = 0 else delay = 1 end

    local partial = RM.lift( J.sanitize("sub_"..tostring(A)..tostring(B)..tostring(outputType).."_async_"..tostring(async)), types.tuple {A,B}, outputType, delay,
    function(sinp)
      local sout = S.cast(S.index(sinp,0),outputType)-S.cast(S.index(sinp,1),outputType)
      if async then sout = sout:disablePipelining() end
      return sout
    end,nil,
    "C.sub")

  return partial
end)

-----------------------------
C.select = memoize(function(ty)
  err(types.isType(ty), "C.select error: input must be type")
  local ITYPE = types.tuple{types.bool(),ty,ty}

  local selm = RM.lift( J.sanitize("C_select_"..tostring(ty)), ITYPE, ty, 1,
    function(sinp) return S.select(S.index(sinp,0), S.index(sinp,1), S.index(sinp,2)) end,nil,
    "C.select" )

  return selm
end)
-----------------------------
C.eq = memoize(function(ty)
  err(types.isType(ty), "C.eq error: input must be type")
  local ITYPE = types.tuple{ty,ty}

  local selm = RM.lift( J.sanitize("C_eq_"..tostring(ty)), ITYPE, types.bool(), 1,
    function(sinp) return S.eq(S.index(sinp,0), S.index(sinp,1)) end, nil,
    "C.eq" )

  return selm
end)

-----------------------------
C.rcp = memoize(function(ty)
  err(types.isType(ty), "C.rcp error: input must be type")
  return f.parameter("finp",ty):rcp():toRigelModule("rcp_"..tostring(ty))
end)

-------------
-- {{idxType,vType},{idxType,vType}} -> {idxType,vType}
-- async: 0 cycle delay
C.argmin = memoize(function(idxType,vType, async, domax)
  local ATYPE = types.tuple {idxType,vType}
  local ITYPE = types.tuple{ATYPE,ATYPE}
  local sinp = S.parameter( "inp", ITYPE )

  local delay

  if async==true then
    delay = 0
  else
    delay = 2
  end

  local name = "argmin"
  if domax then name="argmax" end
  if async then name=name.."_async" end
  name = name.."_"..J.verilogSanitize(tostring(idxType))
  name = name.."_"..J.verilogSanitize(tostring(vType))

  local partial = RM.lift( J.sanitize(name), ITYPE, ATYPE, delay,
    function(sinp)
      local a0 = S.index(sinp,0)
      local a0v = S.index(a0,1)
      local a1 = S.index(sinp,1)
      local a1v = S.index(a1,1)
      local out
      if domax then
        out = S.select(S.ge(a0v,a1v),a0,a1)
      else
        out = S.select(S.le(a0v,a1v),a0,a1)
      end

      if async==true then
        out = out:disablePipelining()
      end
      return out
    end,
    function()
      return CT.argmin(ITYPE,ATYPE,domax)
    end,
    "C.argmin" )

  return partial
end)

------------
-- this returns a function from A[2]->A
-- return |A[0]-A[1]| as a darkroom FN.
-- The largest absolute difference possible is the max value of A - min value, so returning type A is always fine.
-- we fuse this with a cast to 'outputType' just for convenience.
C.absoluteDifference = memoize(function(A,outputType,X)
  err(types.isType(A), "C.absoluteDifference: A must be type")
  err(types.isType(outputType), "C.absoluteDifference: outputType must be type")
  err(X==nil, "C.absoluteDifference: too many arguments")

  local TY = types.array2d(A,2)

  local internalType, internalType_uint
  local internalType_terra

  if A==types.uint(8) then
    -- make sure this doesn't overflow when we add sign bit
    internalType = types.int(9)
    internalType_uint = types.uint(9)
    internalType_terra = int16 -- should yield equivilant output
  else
    assert(false)
  end

  local partial = RM.lift( J.sanitize("absoluteDifference_"..tostring(A).."_"..tostring(outputType)), TY, outputType, 1,
    function(sinp)
      local subabs = S.abs(S.cast(S.index(sinp,0),internalType)-S.cast(S.index(sinp,1),internalType))
      local out = S.cast(subabs, internalType_uint)
      local out = S.cast(out, outputType)
      return out
    end,
    function() return CT.absoluteDifference(A,outputType,internalType_terra) end,
    "C.absoluteDifference")

  return partial
end)

------------
-- returns a darkroom FN that casts type 'from' to type 'to'
-- performs [to](from >> shift)
C.shiftAndCast = memoize(function(from, to, shift)
  err( types.isType(from), "C.shiftAndCast: from type must be type")
  err( types.isType(to), "C.shiftAndCast: to type must be type")
  err( type(shift)=="number", "C.shiftAndCast: shift must be number")

  if shift >= 0 then
    local touint8 = RM.lift( J.sanitize("shiftAndCast_uint" .. from.precision .. "to_uint" .. to.precision.."_shift"..tostring(shift)), from, to, 1,
      function(touint8inp) return S.cast(S.rshift(touint8inp,S.constant(shift,from)), to) end,
      function() return CT.shiftAndCast(from,to,shift) end,
      "C.shiftAndCast")
    return touint8
  else
    local touint8 = RM.lift( J.sanitize("shiftAndCast_uint" .. from.precision .. "to_uint" .. to.precision.."_shift"..tostring(shift)), from, to, 1,
      function(touint8inp) return S.cast(S.lshift(touint8inp,S.constant(-shift,from)), to) end,
      function() return CT.shiftAndCast(from,to,shift) end,
      "C.shiftAndCast")
    return touint8
  end
end)

C.shiftAndCastSaturate = memoize(function(from, to, shift)
  err( types.isType(from), "C.shiftAndCastSaturate: from type must be type")
  err( types.isType(to), "C.shiftAndCastSaturate: to type must be type")
  err( type(shift)=="number", "C.shiftAndCastSaturate: shift must be number")

  local touint8 = RM.lift( J.sanitize("shiftAndCastSaturate_"..tostring(from).."_to_"..tostring(to).."_shift_"..tostring(shift)), from, to, 1,
    function(touint8inp)
      local OT = S.rshift(touint8inp,S.constant(shift,from))
      return S.select(S.gt(OT,S.constant(255,from)),S.constant(255,types.uint(8)), S.cast(OT,to))
    end,
    function() return CT.shiftAndCastSaturate(from,to,shift) end,
    "C.shiftAndCastSaturate")

  return touint8
end)

-------------
-- returns a function of type {A[ConvWidth,ConvWidth], A_const[ConvWidth,ConvWidth]}
-- that convolves the two arrays
C.convolveTaps = memoize(function( A, ConvWidth, shift )
  if shift==nil then shift=7 end

  local TAP_TYPE = types.array2d( A, ConvWidth, ConvWidth )
  local TAP_TYPE_CONST = TAP_TYPE:makeConst()

  local INP_TYPE = types.tuple{types.array2d( A, ConvWidth, ConvWidth ),TAP_TYPE_CONST}
  local inp = R.input( INP_TYPE )

  local packed = R.apply( "packedtup", C.SoAtoAoS(ConvWidth,ConvWidth,{A,A:makeConst()}), inp )
  local conv = R.apply( "partial", RM.map( C.multiply(A,A:makeConst(), types.uint(32)), ConvWidth, ConvWidth ), packed )
  local conv = R.apply( "sum", RM.reduce( C.sum(types.uint(32),types.uint(32),types.uint(32)), ConvWidth, ConvWidth ), conv )
  local conv = R.apply( "touint8", C.shiftAndCast(types.uint(32),A,shift), conv )

  local convolve = RM.lambda( "convolveTaps", inp, conv )
  return convolve
end)

------------
-- returns a function from A[ConvWidth,ConvHeight]->A
C.convolveConstant = memoize(function( A, ConvWidth, ConvHeight, tab, shift, X )
  assert(type(ConvWidth)=="number")
  assert(type(ConvHeight)=="number")
  assert(type(tab)=="table")
  assert(type(shift)=="number")
  assert(X==nil)

  local inp = R.input( types.array2d( A, ConvWidth, ConvHeight ) )
  local r = R.constant( "convkernel", tab, types.array2d( A, ConvWidth, ConvHeight) )

  local packed = R.apply( "packedtup", C.SoAtoAoS(ConvWidth,ConvHeight,{A,A}), R.concat("ptup", {inp,r}) )
  local conv = R.apply( "partial", RM.map( C.multiply(A,A,types.uint(32)), ConvWidth, ConvHeight ), packed )
  local conv = R.apply( "sum", RM.reduce( C.sum(types.uint(32),types.uint(32),types.uint(32)), ConvWidth, ConvHeight ), conv )
  local conv = R.apply( "touint8", C.shiftAndCast( types.uint(32), A, shift ), conv )

  local convolve = RM.lambda( "convolveConstant_W"..tostring(ConvWidth).."_H"..tostring(ConvHeight), inp, conv )
  return convolve
end)

------------
-- returns a function from A[ConvWidth*T,ConvWidth]->A, with throughput T
C.convolveConstantTR = memoize(function( A, ConvWidth, ConvHeight, T, tab, shift, X )
  assert(type(shift)=="number")
  assert(type(T)=="number")
  assert(T<=1)
  assert(type(shift)=="number")
  assert(X==nil)

  local inp = R.input( types.array2d( A, ConvWidth*T, ConvHeight ) )
  local r = R.apply( "convKernel", RM.constSeq( tab, A, ConvWidth, ConvHeight, T ) )

  local packed = R.apply( "packedtup", C.SoAtoAoS(ConvWidth*T,ConvHeight,{A,A}), R.concat("ptup", {inp,r}) )
  local conv = R.apply( "partial", RM.map( C.multiply(A,A,types.uint(32)), ConvWidth*T, ConvHeight ), packed )
  local conv = R.apply( "sum", RM.reduce( C.sum(types.uint(32),types.uint(32),types.uint(32)), ConvWidth*T, ConvHeight ), conv )

  local convseq = RM.lambda( "convseq_T"..tostring(1/T), inp, conv )
------------------
  inp = R.input( R.V(types.array2d( A, ConvWidth*T, ConvHeight )) )
  conv = R.apply( "convseqapply", RM.liftDecimate(RM.liftBasic(convseq)), inp)
  conv = R.apply( "sumseq", RM.RPassthrough(RM.liftDecimate(RM.reduceSeq( C.sum(types.uint(32),types.uint(32),types.uint(32),true), T ))), conv )
  conv = R.apply( "touint8", C.RVPassthrough(C.shiftAndCast( types.uint(32), A, shift )), conv )
  conv = R.apply( "arrayop", C.RVPassthrough(C.arrayop( types.uint(8), 1, 1)), conv)

  local convolve = RM.lambda( "convolve_tr_T"..tostring(1/T), inp, conv )

  return convolve
end)

------------
-- returns a function from A[2][Width,Width]->reduceType
-- 'reduceType' is the precision we do the sum
C.SAD = memoize(function( A, reduceType, Width, X )
  assert(X==nil)

  local inp = R.input( types.array2d( types.array2d(A,2) , Width, Width ) )

  local conv = R.apply( "partial", RM.map( C.absoluteDifference(A,reduceType), Width, Width ), inp )
  local conv = R.apply( "sum", RM.reduce( C.sum(reduceType, reduceType, reduceType), Width, Width ), conv )

  local convolve = RM.lambda( J.sanitize("SAD_"..tostring(A).."_reduceType"..tostring(reduceType).."_Width"..tostring(Width)), inp, conv, nil, "C.SAD" )
  return convolve
end)


C.SADFixed = memoize(function( A, reduceType, Width, X )
  local fixed = require "fixed"
  assert(X==nil)
  fixed.expectFixed(reduceType)
  assert(fixed.extractSigned(reduceType)==false)
  assert(fixed.extractExp(reduceType)==0)

  local inp = R.input( types.array2d( types.array2d(A,2) , Width, Width ) )

  -------
  local ABS_inp = fixed.parameter("abs_inp", types.array2d(A,2))
  local ABS_l, ABS_r = ABS_inp:index(0):lift(0):toSigned(), ABS_inp:index(1):lift(0):toSigned()
  local ABS = (ABS_l-ABS_r):abs():pad(fixed.extractPrecision(reduceType),0)
  ------
  local SUM_inp = fixed.parameter("sum_inp", types.tuple{reduceType,reduceType})
  local SUM_l, SUM_r = SUM_inp:index(0), SUM_inp:index(1)
  local SUM = (SUM_l+SUM_r)

  SUM = SUM:truncate(fixed.extractPrecision(reduceType))
  ------

  local conv = R.apply( "partial", RM.map( ABS:toRigelModule("absoluteDiff"), Width, Width ), inp )
  local conv = R.apply( "sum", RM.reduce( SUM:toRigelModule("ABS_SUM"), Width, Width ), conv )

  local convolve = RM.lambda( "SAD", inp, conv, nil, "C.SADFixed" )
  return convolve
end)


C.SADFixed4 = memoize(function( A, reduceType, Width, X )
  local fixed = require "fixed"
  assert(X==nil)
  fixed.expectFixed(reduceType)
  assert(fixed.extractSigned(reduceType)==false)
  assert(fixed.extractExp(reduceType)==0)

  local inp = R.input( types.array2d( types.array2d(A,2) , Width, Width ) )

  -------
  local ABS_inp = fixed.parameter("abs_inp", types.array2d(A,2))

  local ABSt = {}
  for i=1,4 do
    local ABS_l, ABS_r = ABS_inp:index(0):index(i-1):lift(0):toSigned(), ABS_inp:index(1):index(i-1):lift(0):toSigned()
    ABSt[i] = (ABS_l-ABS_r):abs()
  end

  local ABS = (ABSt[1]+ABSt[2])+(ABSt[3]+ABSt[4])
  ABS = ABS:pad(fixed.extractPrecision(reduceType),0)
  ------
  local SUM_inp = fixed.parameter("sum_inp", types.tuple{reduceType,reduceType})
  local SUM_l, SUM_r = SUM_inp:index(0), SUM_inp:index(1)
  local SUM = (SUM_l+SUM_r)

  SUM = SUM:truncate(fixed.extractPrecision(reduceType))

  ------

  local conv = R.apply( "partial", RM.map( ABS:toRigelModule("absoluteDiff"), Width, Width ), inp )
  local conv = R.apply( "sum", RM.reduce( SUM:toRigelModule("ABS_SUM"), Width, Width ), conv )

  local convolve = RM.lambda( "SAD", inp, conv )
  return convolve
end)

------------
-- takes a function f:A[StencilW,stencilH]->B
-- returns a function from A[T]->B[T]
C.stencilKernel = memoize(function( A, T, imageW, imageH, stencilW, stencilH, f)
  local BASE_TYPE = types.array2d( A, T )
  local inp = R.input( BASE_TYPE )

  local convLB = R.apply( "convLB", C.stencilLinebuffer( A, imageW, imageH, T, -stencilW+1, 0, -stencilH+1, 0 ), inp)
  local convstencils = R.apply( "convstencils", C.unpackStencil( A, stencilW, stencilH, T ), convLB )
  local convpipe = R.apply( "conv", RM.map( f, T ), convstencils )

  local convpipe = RM.lambda( "convpipe_"..f.name.."_W"..tostring(stencilW).."_H"..tostring(stencilH), inp, convpipe, nil,"C.stencilKernel" )
  return convpipe
end)

------------
-- takes a function f:{A[StencilW,StencilH],tapType}->B
-- returns a function that goes from A[T]->B[T]. Applies f using a linebuffer
C.stencilKernelTaps = memoize(function( A, T, tapType, imageW, imageH, stencilW, stencilH, f )
  assert(type(stencilW)=="number")
  assert(type(stencilH)=="number")

  local BASE_TYPE = types.array2d( A, T )
  local ITYPE = types.tuple{BASE_TYPE, tapType}
  local rawinp = R.input( ITYPE )

  local inp = R.apply("idx0",C.index(ITYPE,0),rawinp)
  local taps = R.apply("idx1",C.index(ITYPE,1),rawinp)

  local convLB = R.apply( "convLB", C.stencilLinebuffer( A, imageW, imageH, T, -stencilW+1, 0, -stencilH+1, 0 ), inp)
  local convstencils = R.apply( "convstencils", C.unpackStencil( A, stencilW, stencilH, T ) , convLB )

  local st_tap_inp = R.apply( "broad", C.broadcast(tapType,T), taps )
  st_tap_inp = R.concat("sttapinp",{convstencils,st_tap_inp})
  local ST_TYPE = types.array2d( A, stencilW, stencilH )
  st_tap_inp = R.apply("ST",C.SoAtoAoS(T,1,{ST_TYPE,tapType}),st_tap_inp)
  local convpipe = R.apply( "conv", RM.map( f, T ), st_tap_inp )

  local convpipe = RM.lambda( "convpipe", rawinp, convpipe )
  return convpipe
end)
-------------
-- f should be a _lua_ function that takes two arguments, (internalW,internalH), and returns the
-- inner function based on this W,H. We have to do this for alignment reasons.
-- f should return a handshake function
-- timingFifo: include a fifo to improve timing. true by default
C.padcrop = memoize(function( A, W, H, T, L, Right, B, Top, borderValue, f, timingFifo, X )
  err( type(W)=="number", "padcrop: W should be number")
  err( type(H)=="number", "padcrop: H should be number")
  err( type(T)=="number", "padcrop: T should be number")
  err( type(L)=="number", "padcrop: L should be number")
  err( type(Right)=="number", "padcrop: Right should be number")
  err( type(B)=="number", "padcrop: B should be number")
  err( type(Top)=="number", "padcrop: Top should be number")
  err( type(f)=="function", "padcrop: f should be lua function")

  err( X==nil, "padcrop: too many arguments" )
  err( timingFifo==nil or type(timingFifo)=="boolean", "padcrop: timingFIFO must be nil or boolean" )
  if timingFifo==nil then timingFifo=true end

  local RW_TYPE = types.array2d( A, T ) -- simulate axi bus
  local hsfninp = R.input( R.Handshake(RW_TYPE) )

  local internalL = J.upToNearest(T,L)
  local internalR = J.upToNearest(T,Right)

  local fifos = {}
  local statements = {}

  local internalW, internalH = W+internalL+internalR,H+B+Top

  local out = R.apply("pad", RM.liftHandshake(RM.padSeq(A, W, H, T, internalL, internalR, B, Top, borderValue)), hsfninp)

  if timingFifo then
    -- this FIFO is only for improving timing
    table.insert( fifos, R.instantiateRegistered("f1",RM.fifo(types.array2d(A,T),128)) )
    table.insert( statements, R.applyMethod("s3",fifos[#fifos],"store",out) )
    out = R.applyMethod("l13",fifos[#fifos],"load")
  end

  -----------------
  local internalFn = f(internalW, internalH)
  local out = R.apply("HH",internalFn, out)
  local padL = internalL-L
  local padR = internalR-Right
  local fnOutType = R.extractData(internalFn.outputType):arrayOver()
  local out = R.apply("crop",RM.liftHandshake(RM.liftDecimate(C.cropHelperSeq(fnOutType, internalW, internalH, T, padL+Right+L, padR, B+Top, 0))), out)

  if timingFifo then
    -- this FIFO is only for improving timing
    table.insert( fifos, R.instantiateRegistered("f2",RM.fifo(types.array2d(fnOutType,T),128)) )
    table.insert( statements, R.applyMethod("s2",fifos[#fifos],"store",out) )
    out = R.applyMethod("l2",fifos[#fifos],"load")
  end
  -----------------

  table.insert(statements,1,out)

  local name = J.sanitize("padcrop_"..tostring(A).."L"..tostring(L).."_R"..tostring(Right).."_B"..tostring(B).."_T"..tostring(Top).."_W"..tostring(W).."_H"..tostring(H)..internalFn.name)

  local hsfn
  if timingFifo then
    hsfn = RM.lambda(name, hsfninp, R.statements(statements), fifos )
  else
    hsfn = RM.lambda(name, hsfninp, out)
  end

  return hsfn
end)

--------
function C.stencilKernelPadcrop(A,W,H,T,L,Right,B,Top,borderValue,f,timingFifo,X)
  local function finternal(IW,IH)
    return RM.makeHandshake(C.stencilKernel(A,T,IW,IH,Right+L+1,Top+B+1,f))
  end
  return C.padcrop(A,W,H,T,L,Right,B,Top,borderValue,finternal,timingFifo)
end

-- f should take (internalW,internalH) parameters
function C.stencilKernelPadcropUnpure(A,W,H,T,L,Right,B,Top,borderValue,f,timingFifo,X)
  local function finternal(IW,IH)
    return RM.makeHandshake(C.stencilKernel(A,T,IW,IH,Right+L+1,Top+B+1,f(IW,IH)))
  end
  return C.padcrop(A,W,H,T,L,Right,B,Top,borderValue,finternal,timingFifo)
end
-------------
local function invtable(bits)
  local out = {}
--[=[  local terra inv(a:uint32)
    if a==0 then
      return 0
    else
      var o = ([math.pow(2,17)]/([uint32](255)+a))-[uint32](256)
      if o>255 then return 255 end
      return o
    end
end]=]

  local function round(x) if (x%1>=0.5) then return math.ceil(x) else return math.floor(x) end end

  for i=0,math.pow(2,bits)-1 do
    local v = (math.pow(2,17)/(256+i)) - 256
    if v>255 then v = 255 end
    v = round(v)
    table.insert(out, v)
  end
  return out
end

function stripMSB(totalbits)
  local ITYPE = types.uint(totalbits)
  return RM.lift("stripMSB",ITYPE,types.uint(totalbits-1),0,
    function(sinp) return S.cast(sinp,types.uint(totalbits-1)) end,
    function() return CT.stripMSB(totalbits) end)
end

-- We want to calculate 1/x
--
-- we take the input x, and convert it to the floating point representation 1.ffffffff * 2^n
-- where f is the fractional component.
--
-- observe that (1/(1+fffff)) is between 0.5 and 1
--
-- in integer form, we have input 9 bit input in form (2^8+ffffffff) * 2^n
-- So we compute 2^9/((2^8+ffffffff)*2^n) = 2^(-n) * (2^9 / (2^8+ffffffff) )
--
-- put the (2^9 / (2^8+ffffffff) ) part in a lookup table. Since this is from 0.5 to 1,
-- we normalize to make good use of the bits in the LUT:
-- (2^17 / (2^8 + ffffffff)) - 256, which goes from 0 to 255
--
-- Plug this back in, and to find the real value, we have:
-- LUT(ffffffff) + 256, which has exponant n-17
function C.lutinvert(ty)
  local fixed = require "fixed"
  fixed.expectFixed(ty)
  local signed = fixed.extractSigned(ty)

  --------------------
  local ainp = fixed.parameter("ainp",ty)
  local a = ainp:hist("lutinvert_input")
  local a_sign
  if signed then
    a_sign = a:sign()
    a = a:abs()
  end
  local a_exp = a:msb(9)
  local a_float, a_min, a_max = a:float(a_exp,9)
  local aout
  if signed then
    aout = fixed.tuple({a_float,a_exp,a_sign})
  else
    aout = fixed.tuple({a_float,a_exp})
  end
  local afn = aout:toRigelModule("lutinvert_a")
  --------------------
  local lutbits = 8
  ------------
  local binp
  if signed then
    binp = fixed.parameter("binp", types.tuple{types.uint(8),types.int(8),types.bool()} )
  else
    binp = fixed.parameter("binp", types.tuple{types.uint(8),types.int(8)} )
  end
  local b_inv = binp:index(0)
  local b_exp = binp:index(1)
  local b = (b_inv:cast(types.uint(9))+fixed.plainconstant(256,types.uint(9))):liftFloat(-a_max-17,-a_min-17+8, b_exp:neg()-fixed.plainconstant(17, types.int(8)) )
  if signed then b = b:addSign(binp:index(2)) end
  b = b:hist("lutinvert_output")
  local bfn = b:toRigelModule("lutinvert_b")
  ---------------

  local inp = R.input( ty )
  local aout = R.apply( "a", afn, inp )
  local aout_float = R.apply("aout_float", C.index(afn.outputType,0), aout)
  local aout_exp = R.apply("aout_exp", C.index(afn.outputType,1), aout)
  local aout_sign
  if signed then aout_sign = R.apply("aout_sign", C.index(afn.outputType,2), aout) end

  local aout_float_lsbs = R.apply("aout_float_lsbs", stripMSB(9), aout_float)

  local inv = R.apply("inv", RM.lut(types.uint(lutbits), types.uint(8), invtable(lutbits)), aout_float_lsbs)
  local out = R.apply( "b", bfn, R.concat("binp",{inv,aout_exp,aout_sign}) )
  local fn = RM.lambda( "lutinvert", inp, out )

  return fn, fn.outputType
end
-------------
C.stencilLinebufferPartialOffsetOverlap = memoize(function( A, w, h, T, xmin, xmax, ymin, ymax, offset, overlap )
  J.map({T,w,h,xmin,xmax,ymin,ymax}, function(i) assert(type(i)=="number") end)
  assert(T<=1); assert(w>0); assert(h>0);
  assert(xmin<xmax)
  assert(ymin<ymax)
  assert(xmax==0)
  assert(ymax==0)

  local ST_W = -xmin+1
  local ssr_region = ST_W - offset - overlap
  local stride = ssr_region*T
  assert(stride==math.floor(stride))

  local LB = RM.makeHandshake(RM.linebuffer( A, w, h, 1, ymin ))
  local SSR = RM.liftHandshake(RM.waitOnInput(RM.SSRPartial( A, T, xmin, ymin, stride, true )))

  local inp = R.input( LB.inputType )
  local out = R.apply("LB", LB, inp)
  out = R.apply("SSR", SSR, out)
  out = R.apply("slice", RM.makeHandshake(C.slice(types.array2d(A,ST_W,-ymin+1), 0, stride+overlap-1, 0,-ymin)), out)

  return RM.lambda("stencilLinebufferPartialOverlap",inp,out)
end)

-------------
C.fifo = memoize(function(ty,size,X)
  err( types.isType(ty), "C.fifo: type must be a type" )
  err( R.isBasic(ty), "C.fifo: type must be basic type" )
  err( type(size)=="number" and size>0, "C.fifo: size must be number > 0" )
  err( X==nil, "C.fifo: too many arguments" )
  
  local inp = R.input(R.Handshake(ty))
  local regs = {R.instantiateRegistered("f1",RM.fifo(ty,size))}
  return RM.lambda("C_FIFO_"..tostring(ty).."_size"..tostring(size), inp, R.statements{R.applyMethod("l1",regs[1],"load"),R.applyMethod("s1",regs[1],"store",inp)}, regs, "C.fifo", {size=size} )
end)

-------------
-- FIFO with loop support
function C.fifoLoop(fifos,statements,A,inp,size,name, csimOnly, X)
  assert(type(name)=="string")
  assert(X==nil)

  table.insert( fifos, R.instantiateRegistered(name, RM.fifo(A,size,nil,nil,nil,nil,csimOnly)) )
  table.insert( statements, R.applyMethod("s"..tostring(#fifos),fifos[#fifos],"store",inp) )
  return R.applyMethod("l"..tostring(#fifos),fifos[#fifos],"load")
end
-------------

-- HACK: this should really be in this file, but it needs to be in the other file to satisfy dependencies in old code
C.compose = RM.compose
C.SoAtoAoS = RM.SoAtoAoS

-- takes {Handshake(a[W,H]), Handshake(b[W,H]),...} to Handshake( {a,b}[W,H] )
-- typelist should be a table of pure types
C.SoAtoAoSHandshake = memoize(function( W, H, typelist, X )
  assert(X==nil)
  local f = modules.SoAtoAoS(W,H,typelist)
  f = modules.makeHandshake(f)

  return C.compose( J.sanitize("SoAtoAoSHandshake_W"..tostring(W).."_H"..tostring(H).."_"..tostring(typelist)), f, modules.packTuple( J.map(typelist, function(t) return types.array2d(t,W,H) end) ) )
end)

-- Takes A[W,H] to A[W,H], but with a border around the edges determined by L,R,B,T
function C.border(A,W,H,L,R,B,T,value)
  J.map({W,H,L,R,T,B,value},function(n) assert(type(n)=="number") end)
  local res = {kind="border",generator="C.border",L=L,R=R,T=T,B=B,value=value}
  res.inputType = types.array2d(A,W,H)
  res.outputType = res.inputType
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.delay = 0

  if terralib~=nil then res.terraModule = CT.border(res,A,W,H,L,R,B,T,value) end
  return rigel.newFunction(res)
end


-- takes basic->basic to RV->RV
function C.RVPassthrough(f)
  return modules.RPassthrough(modules.liftDecimate(modules.liftBasic(f)))
end

-- fully parallel up/down scale
-- if scaleX,Y > 1 then this is upsample
-- if scaleX,Y < 1 then this is downsample
C.scale = memoize(function( A, w, h, scaleX, scaleY )
  assert(types.isType(A))
  assert(type(w)=="number")
  assert(type(h)=="number")
  assert(type(scaleX)=="number")
  assert(type(scaleY)=="number")

  local res = { kind="scale", scaleX=scaleX, scaleY=scaleY}
  res.inputType = types.array2d( A, w, h )
  res.outputType = types.array2d( A, w*scaleX, h*scaleY )
  res.delay = 0

  if terralib~=nil then res.terraModule = CT.scale(res, A, w, h, scaleX, scaleY ) end

  return rigel.newFunction(res)
end)


-- V -> RV
C.downsampleSeq = memoize(function( A, W, H, T, scaleX, scaleY, X )
  err( types.isType(A), "C.downsampleSeq: A must be type")
  err( type(W)=="number", "C.downsampleSeq: W must be number")
  err( type(H)=="number", "C.downsampleSeq: H must be number")
  err( type(T)=="number", "C.downsampleSeq: T must be number")
  err( type(scaleX)=="number", "C.downsampleSeq: scaleX must be number")
  err( type(scaleY)=="number", "C.downsampleSeq: scaleY must be number")
  err( scaleX>=1, "C.downsampleSeq: scaleX must be >=1")
  err( scaleY>=1, "C.downsampleSeq: scaleY must be >=1")
  err( X==nil, "C.downsampleSeq: too many arguments" )

  if scaleX==1 and scaleY==1 then
    return C.identity(A)
  end

  local inp = rigel.input( rigel.V(types.array2d(A,T)) )
  local out = inp
  if scaleY>1 then
    out = rigel.apply("downsampleSeq_Y", modules.liftDecimate(modules.downsampleYSeq( A, W, H, T, scaleY )), out)
  end
  if scaleX>1 then
    local mod = modules.liftDecimate(modules.downsampleXSeq( A, W, H, T, scaleX ))
    if scaleY>1 then mod=modules.RPassthrough(mod) end

    out = rigel.apply("downsampleSeq_X", mod, out)
    local downsampleT = math.max(T/scaleX,1)
    if downsampleT<T then
      -- technically, we shouldn't do this without lifting to a handshake - but we know this can never stall, so it's ok
      out = rigel.apply("downsampleSeq_incrate", modules.RPassthrough(modules.changeRate(A,1,downsampleT,T)), out )
    elseif downsampleT>T then assert(false) end
  end
  return modules.lambda( J.sanitize("downsampleSeq_"..tostring(A).."_W"..tostring(W).."_H"..tostring(H).."_T"..tostring(T).."_scaleX"..tostring(scaleX).."_scaleY"..tostring(scaleY)), inp, out,nil,"C.downsampleSeq")
end)


-- this is always Handshake
-- always has type A[T]->A[T]
C.upsampleSeq = memoize(function( A, W, H, T, scaleX, scaleY, X )
  err( types.isType(A), "C.upsampleSeq: A must be type")
  err( type(W)=="number", "C.upsampleSeq: W must be number")
  err( type(H)=="number", "C.upsampleSeq: H must be number")
  err( type(T)=="number", "C.upsampleSeq: T must be number")
  err( type(scaleX)=="number", "C.upsampleSeq: scaleX must be number")
  err( type(scaleY)=="number", "C.upsampleSeq: scaleY must be number")
  err( scaleX>=1, "C.upsampleSeq: scaleX must be >=1")
  err( scaleY>=1, "C.upsampleSeq: scaleY must be >=1")
  err( X==nil, "C.upsampleSeq: too many arguments" )

  if scaleX==1 and scaleY==1 then
    return C.identity(types.array2d(A,T))
  end

  local inner
  if scaleY>1 and scaleX==1 then
    inner = modules.liftHandshake(modules.upsampleYSeq( A, W, H, T, scaleY ))
  elseif scaleX>1 and scaleY==1 then
    inner = modules.upsampleXSeq( A, T, scaleX )
  else
    local f = modules.upsampleXSeq( A, T, scaleX )
    inner = C.compose( J.sanitize("upsampleSeq_"..tostring(A).."_W"..tostring(W).."_H"..tostring(H).."_T"..tostring(T).."_scaleX"..tostring(scaleX).."_scaleY"..tostring(scaleY)), f, modules.liftHandshake(modules.upsampleYSeq( A, W, H, T, scaleY )),nil,"C.upsampleSeq")
  end

    return inner
end)


-- takes A to A[T] by duplicating the input
C.broadcast = memoize(function(A,W,H)
  err( types.isType(A), "C.broadcast: A must be type A")
  rigel.expectBasic(A)
  err( type(W)=="number", "broadcast: W should be number")
  if H==nil then return C.broadcast(A,W,1) end
  err( type(H)=="number", "broadcast: H should be number")

  local OT = types.array2d(A, W, H)

  return modules.lift( J.sanitize("Broadcast_"..tostring(A).."_W"..tostring(W).."_H"..tostring(H)),A,OT,0,
    function(sinp) return S.cast(S.tuple(J.broadcast(sinp,W*H)),OT) end,
    function() return CT.broadcast(A,W,H,OT) end,
    "C.broadcast")
end)
C.arrayop=C.broadcast

-- extractStencils : A[w,h] -> A[(xmax-xmin+1)*(ymax-ymin+1)][w,h]
-- min, max ranges are inclusive
C.stencil = memoize(function( A, w, h, xmin, xmax, ymin, ymax )
  assert( type(xmin)=="number" )
  assert( type(xmax)=="number" )
  assert( xmax>=xmin )
  assert( type(ymin)=="number" )
  assert( type(ymax)=="number" )
  assert( ymax>=ymin )

  rigel.expectBasic(A)
  if A:isArray() then error("Input to extract stencils must not be array") end

  local res = {kind="stencil", type=A, w=w, h=h, xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax, generator="C.stencil" }
  res.delay=0
  res.inputType = types.array2d(A,w,h)
  res.outputType = types.array2d(types.array2d(A,xmax-xmin+1,ymax-ymin+1),w,h)
  res.sdfInput, res.sdfOutput = {{1,1}},{{1,1}}
  res.name = J.sanitize("Stencil_"..tostring(A).."_w"..tostring(w).."_h"..tostring(h).."_xmin"..tostring(xmin).."_xmax"..tostring(xmax).."_ymin"..tostring(ymin).."_ymax"..tostring(ymax))
  res.stateful=false

  if terralib~=nil then res.terraModule = CT.stencil(res, A, w, h, xmin, xmax, ymin, ymax ) end

  return rigel.newFunction(res)
end)

-- this applies a border around the image. Takes A[W,H] to A[W,H], but with a border. Sequentialized to throughput T.
C.borderSeq = memoize(function( A, W, H, T, L, R, B, Top, Value, X )
  err( types.isType(A), "borderSeq: type must be type")
  J.map({W=W or "W",H = H or "H",T = T or "T",L = L or "L",R=R or "R",B = B or "B",Top = Top or "Top",Value = Value or "Value"},function(n,k) err(type(n)=="number","borderSeq: "..k.." must be number") end)
  err( X==nil, "borderSeq: too many arguments")

  local inpType = types.tuple{types.tuple{types.uint(16),types.uint(16)},A}

  local modname = "BorderSeq_"..J.verilogSanitize(tostring(A)).."_W"..tostring(W).."_H"..tostring(H).."_T"..tostring(T).."_L"..tostring(L).."_R"..tostring(R).."_B"..tostring(B).."_Top"..tostring(Top).."_Value"..tostring(Value)

  local f = modules.lift( modname, inpType, A, 0,
    function(inp)
      local inpx, inpy = S.index(S.index(inp,0),0), S.index(S.index(inp,0),1)

      local lcheck = S.constant(false,types.bool())
      if L~=0 then lcheck = S.lt(inpx,S.constant(L,types.uint(16))) end -- verilator lint workaround

      local horizontal = S.__or(lcheck,S.ge(inpx,S.constant(W-R,types.uint(16))))

      local bcheck = S.constant(false,types.bool())
      if B~=0 then bcheck = S.lt(inpy,S.constant(B,types.uint(16))) end -- verilator lint workaround

      local vert = S.__or(bcheck,S.ge(inpy,S.constant(H-Top,types.uint(16))))
      local outside = S.__or(horizontal,vert)
      return S.select(outside,S.constant(Value,A), S.index(inp,1) )
    end,
    function() return CT.borderSeq( A, W, H, T, L, R, B, Top, Value, inpType ) end)

  return modules.liftXYSeqPointwise( modname, "C.borderSeq", f, W, H, T )
end)

-- This is the same as CropSeq, but lets you have L,R not be T-aligned
-- All it does is throws in a shift register to alter the horizontal phase
C.cropHelperSeq = memoize(function( A, W, H, T, L, R, B, Top, X )
  err(X==nil, "cropHelperSeq, too many arguments")
  err(type(T)=="number","T must be number")
  if L%T==0 and R%T==0 then return modules.cropSeq( A, W, H, T, L, R, B, Top ) end

  err( (W-L-R)%T==0, "cropSeqHelper, (W-L-R)%T~=0")

  local RResidual = R%T
  local inp = rigel.input( types.array2d( A, T ) )
  local out = rigel.apply( "SSR", modules.SSR( A, T, -RResidual, 0 ), inp)
  out = rigel.apply( "slice", C.slice( types.array2d(A,T+RResidual), 0, T-1, 0, 0), out)
  out = rigel.apply( "crop", modules.cropSeq(A,W,H,T,L+RResidual,R-RResidual,B,Top), out )

  return modules.lambda( J.sanitize("cropHelperSeq_"..tostring(A).."_W"..W.."_H"..H.."_T"..T.."_L"..L.."_R"..R.."_B"..B.."_Top"..Top), inp, out )
end)


C.stencilLinebuffer = memoize(function( A, w, h, T, xmin, xmax, ymin, ymax )
  err(types.isType(A), "stencilLinebuffer: A must be type")

  err(type(T)=="number","stencilLinebuffer: T must be number")
  err(type(w)=="number","stencilLinebuffer: w must be number")
  err(type(h)=="number","stencilLinebuffer: h must be number")
  err(type(xmin)=="number","stencilLinebuffer: xmin must be number")
  err(type(xmax)=="number","stencilLinebuffer: xmax must be number")
  err(type(ymin)=="number","stencilLinebuffer: ymin must be number")
  err(type(ymax)=="number","stencilLinebuffer: ymax must be number")

  err(T>=1, "stencilLinebuffer: T must be >=1");
  err(w>0,"stencilLinebuffer: w must be >0");
  err(h>0,"stencilLinebuffer: h must be >0");
  err(xmin<=xmax,"stencilLinebuffer: xmin>xmax")
  err(ymin<=ymax,"stencilLinebuffer: ymin>ymax")
  err(xmax==0,"stencilLinebuffer: xmax must be 0")
  err(ymax==0,"stencilLinebuffer: ymax must be 0")

  return C.compose( J.sanitize("stencilLinebuffer_A"..tostring(A).."_w"..w.."_h"..h.."_T"..T.."_xmin"..tostring(math.abs(xmin)).."_ymin"..tostring(math.abs(ymin))), modules.SSR( A, T, xmin, ymin), modules.linebuffer( A, w, h, T, ymin ), "C.stencilLinebuffer" )
end)

C.stencilLinebufferPartial = memoize(function( A, w, h, T, xmin, xmax, ymin, ymax )
  J.map({T,w,h,xmin,xmax,ymin,ymax}, function(i) assert(type(i)=="number") end)
  assert(T<=1); assert(w>0); assert(h>0);
  assert(xmin<xmax)
  assert(ymin<ymax)
  assert(xmax==0)
  assert(ymax==0)

  -- SSRPartial need to be able to stall the linebuffer, so we must do this with handshake interfaces. Systolic pipelines can't stall each other
  return C.compose( J.sanitize("stencilLinebufferPartial_A"..tostring(A).."_W"..tostring(w).."_H"..tostring(h)), modules.liftHandshake(modules.waitOnInput(modules.SSRPartial( A, T, xmin, ymin ))), modules.makeHandshake(modules.linebuffer( A, w, h, 1, ymin )), "C.stencilLinebufferPartial" )
end)


-- purely wiring. This should really be implemented as a lift.
C.unpackStencil = memoize(function( A, stencilW, stencilH, T, arrHeight, X )
  assert(types.isType(A))
  assert(type(stencilW)=="number")
  assert(stencilW>0)
  assert(type(stencilH)=="number")
  assert(stencilH>0)
  assert(type(T)=="number")
  assert(T>=1)
  err(arrHeight==nil, "Error: NYI - unpackStencil on non-height-1 arrays")
  assert(X==nil)

  local res = {kind="unpackStencil", stencilW=stencilW, stencilH=stencilH,T=T,generator="C.unpackStencil"}
  res.inputType = types.array2d( A, stencilW+T-1, stencilH)
  res.outputType = types.array2d( types.array2d( A, stencilW, stencilH), T )
  res.sdfInput, res.sdfOutput = {{1,1}}, {{1,1}}
  res.stateful = false
  res.delay=0
  res.name = J.sanitize("unpackStencil_"..tostring(A).."_W"..tostring(stencilW).."_H"..tostring(stencilH).."_T"..tostring(T))

  if terralib~=nil then res.terraModule = CT.unpackStencil(res, A, stencilW, stencilH, T, arrHeight) end

  res.systolicModule = Ssugar.moduleConstructor(res.name)
  local sinp = S.parameter("inp", res.inputType)
  local out = {}
  for i=1,T do
    out[i] = {}
    for y=0,stencilH-1 do
      for x=0,stencilW-1 do
        out[i][y*stencilW+x+1] = S.index( sinp, x+i-1, y )
      end
    end
  end

  res.systolicModule:addFunction( S.lambda("process", sinp, S.cast( S.tuple(J.map(out,function(n) return S.cast( S.tuple(n), types.array2d(A,stencilW,stencilH) ) end)), res.outputType ), "process_output", nil, nil, S.CE("process_CE") ) )
  --res.systolicModule:addFunction( S.lambda("reset", S.parameter("r",types.null()), nil, "ro" ) )

  return rigel.newFunction(res)
end)


-- if index==true, then we return a value, not an array
C.slice = memoize(function( inputType, idxLow, idxHigh, idyLow, idyHigh, index, X )
  err( types.isType(inputType),"slice first argument must be type" )
  err( type(idxLow)=="number", "slice idxLow must be number")
  err( type(idxHigh)=="number", "slice idxHigh must be number")
  err( index==nil or type(index)=="boolean", "index must be bool")
  err( X==nil, "C.slice: too many arguments")

  if inputType:isTuple() then
    assert( idxLow < #inputType.list )
    assert( idxHigh < #inputType.list )
    assert( idxLow == idxHigh ) -- NYI
    assert( index )
    local OT = inputType.list[idxLow+1]

    return modules.lift( J.sanitize("index_"..tostring(inputType).."_"..idxLow), inputType, OT, 0,
      function(systolicInput) return S.index( systolicInput, idxLow ) end,
      function() return CT.sliceTup(inputType,OT,idxLow) end,
      "C.slice")

  elseif inputType:isArray() then
    local W = (inputType:arrayLength())[1]
    local H = (inputType:arrayLength())[2]
    err(idxLow<W,"slice: idxLow>=W")
    err(idxHigh<W, "slice: idxHigh>=W")
    assert(type(idyLow)=="number")
    assert(type(idyHigh)=="number")
    assert(idyLow<H)
    err(idyHigh<H, "idyHigh>=H")
    assert(idxLow<=idxHigh)
    assert(idyLow<=idyHigh)
    local OT

    if index then
      OT = inputType:arrayOver()
    else
      OT = types.array2d( inputType:arrayOver(), idxHigh-idxLow+1, idyHigh-idyLow+1 )
    end

    return modules.lift( J.sanitize("slice_type"..tostring(inputType).."_xl"..idxLow.."_xh"..idxHigh.."_yl"..idyLow.."_yh"..idyHigh.."_index"..tostring(index)), inputType, OT, 0,
      function(systolicInput)
        local systolicOutput = S.tuple( J.map( J.range2d(idxLow,idxHigh,idyLow,idyHigh), function(i) return S.index( systolicInput, i[1], i[2] ) end ) )
        systolicOutput = S.cast( systolicOutput, OT )

        if index then
          systolicOutput = S.index( systolicInput, idxLow, idyLow )
        end
        return systolicOutput
      end,
      function()
        if index then
          local OT = inputType:arrayOver()
          return CT.sliceArrIdx(inputType,OT,idxLow,idyLow,idxHigh,idyHigh,W)
        else
          return CT.sliceArr(inputType,OT,idxLow,idyLow,idxHigh,idyHigh,W)
        end
      end,
      "C.slice")
  else
    err(false, "C.index input must be tuple or array but is "..tostring(inputType))
  end
end)

function C.index( inputType, idx, idy, X )
  err( types.isType(inputType), "first input to index must be a type" )
  err( type(idx)=="number", "index idx must be number")
  assert(X==nil)
  if idy==nil then idy=0 end
  return C.slice( inputType, idx, idx, idy, idy, true )
end


function C.gaussian(W,sigma)
  local center = math.floor(W/2)
  local tab = {}
  local sum = 0
  for y=0,W-1 do
    for x=0,W-1 do
      local a = 1/(sigma*math.sqrt(2*math.pi))
      local dist = math.sqrt(math.pow(x-center,2)+math.pow(y-center,2))
      local v = a*math.exp(-(dist*dist)/(2*sigma*sigma))
      sum = sum + v
      table.insert(tab,v)
    end
  end

  local newsum = 0
  for i=1,#tab do
    tab[i] = math.floor((tab[i]*64/sum)+0.4)
    newsum = newsum + tab[i]
  end

  tab[center*W+center] = tab[center*W+center] + (64-newsum)

  return tab
end

C.plusConst = memoize(function(ty, value)
  err(types.isType(ty),"plus100: expected type input")
  err(type(value)=="number","plusConst expected numeric input")
  local plus100mod = RM.lift( J.sanitize("plus_"..tostring(ty).."_"..tostring(value)), ty,ty , 10, function(plus100inp) return plus100inp + S.constant(value,ty) end, function() return CT.plusConsttfn(ty,value) end )
  return plus100mod
end)

function C.plus100(ty) return C.plusConst(ty,100) end

__linearpipelinecnt = 0
-- convert an array of rigel modules into a straight pipeline
-- pipeline starts at index 1, ends at index N
function C.linearPipeline(t,modulename)
  err(modulename==nil or type(modulename)=="string","linearPipeline: modulename must be string")

  if modulename==nil then
    modulename="linearpipeline"..tostring(__linearpipelinecnt)
    __linearpipelinecnt = __linearpipelinecnt+1
  end

  local inp = R.input(t[1].inputType)
  local out = inp

  for k,v in ipairs(t) do
    out = R.apply("linearPipe"..k,v,out)
  end

  return RM.lambda(modulename,inp,out)
end

return C
