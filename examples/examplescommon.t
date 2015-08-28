local d = require "darkroom"
local C = {}

-- A -> A[W,H]
C.arrayop = memoize(function(A,W,H)
  local inp = d.input(A)
  return d.lambda("arrayop_"..tostring(A).."_W"..W.."_H"..tostring(H),inp,d.array2d("ao",{inp},W,H))
end)

------------
-- return A*B as a darkroom FN. A,B are types
-- returns something of type outputType
function C.multiply(A,B,outputType)
  local sinp = S.parameter( "inp", types.tuple {A,B} )
  local partial = d.lift( "partial", types.tuple {A,B}, outputType, 1,
                          terra( a : &tuple(A:toTerraType(),B:toTerraType()), out : &outputType:toTerraType() )
                            @out = [outputType:toTerraType()](a._0)*[outputType:toTerraType()](a._1)
                  end, sinp, S.cast(S.index(sinp,0),outputType)*S.cast(S.index(sinp,1),outputType) )
  return partial
end
------------
-- return A+B as a darkroom FN. A,B are types
-- returns something of type outputType
function C.sum(A,B,outputType)
  local sinp = S.parameter( "inp", types.tuple {A,B} )
  local partial = d.lift( "sum", types.tuple {A,B}, outputType, 1,
                          terra( a : &tuple(A:toTerraType(),B:toTerraType()), out : &outputType:toTerraType() )
                            @out = [outputType:toTerraType()](a._0)+[outputType:toTerraType()](a._1)
                  end, sinp, S.cast(S.index(sinp,0),outputType)+S.cast(S.index(sinp,1),outputType) )
  return partial
end

-------------
-- {{idxType,vType},{idxType,vType}} -> {idxType,vType}
-- async: 0 cycle delay
function C.argmin(idxType,vType, async)
  local ATYPE = types.tuple {idxType,vType}
  local ITYPE = types.tuple{ATYPE,ATYPE}
  local sinp = S.parameter( "inp", ITYPE )

  local a0 = S.index(sinp,0)
  local a0v = S.index(a0,1)
  local a1 = S.index(sinp,0)
  local a1v = S.index(a1,1)

  local delay = 2
  local out = S.select(S.le(a0v,a1v),a0,a1)

  if async==true then 
    out = out:disablePipelining() 
    delay = 0
  end

  local partial = d.lift( "argmin_async"..tostring(async), ITYPE, ATYPE, delay,
                          terra( a : &ITYPE:toTerraType(), out : &ATYPE:toTerraType() )
                            if a._0._1 <= a._1._1 then
                              @out = a._0
                            else
                              @out = a._1
                            end
                          end, sinp, out )
  return partial
end

------------
-- this returns a function from A[2]->outputType
-- return |A[0]-A[1]| as a darkroom FN. A is a type
-- returns something of type outputType
function C.absoluteDifference(A,outputType)
  local TY = types.array2d(A,2)
  local sinp = S.parameter( "inp", TY )
  local internalType = types.int(32)
  local partial = d.lift( "absoluteDifference", TY, outputType, 1,
                          terra( a : &(A:toTerraType())[2], out : &outputType:toTerraType() )
                            @out = [outputType:toTerraType()]([int32]((@a)[0])-[int32]((@a)[1]))
                          end, sinp, S.cast(S.abs(S.cast(S.index(sinp,0),internalType)-S.cast(S.index(sinp,1),internalType)), outputType) )
  return partial
end

------------
-- returns a darkroom FN that casts type 'from' to type 'to'
-- performs [to](from >> shift)
function C.shiftAndCast(from, to, shift)
  local touint8inp = S.parameter("inp", from)
  local touint8 = d.lift( "touint8", from, to, 1, terra( a : &from:toTerraType(), out : &to:toTerraType() ) @out = [uint8](@a >> shift) end, touint8inp, S.cast(S.rshift(touint8inp,S.constant(shift,from)), to) )
  return touint8
end
-------------
-- returns a function of type {A[ConvWidth,ConvWidth], A_const[ConvWidth,ConvWidth]}
-- that convolves the two arrays
function C.convolveTaps(A,ConvWidth)
  local TAP_TYPE = types.array2d( A, ConvWidth, ConvWidth )
  local TAP_TYPE_CONST = TAP_TYPE:makeConst()

  local INP_TYPE = types.tuple{types.array2d( A, ConvWidth, ConvWidth ),TAP_TYPE_CONST}
  local inp = d.input( INP_TYPE )

  local packed = d.apply( "packedtup", d.SoAtoAoS(ConvWidth,ConvWidth,{A,A:makeConst()}), inp )
  local conv = d.apply( "partial", d.map( C.multiply(A,A:makeConst(), types.uint(32)), ConvWidth, ConvWidth ), packed )
  local conv = d.apply( "sum", d.reduce( C.sum(types.uint(32),types.uint(32),types.uint(32)), ConvWidth, ConvWidth ), conv )
  local conv = d.apply( "touint8", C.shiftAndCast(types.uint(32),A,7), conv )

  local convolve = d.lambda( "convolve", inp, conv )
  return convolve
end

------------
-- returns a function from A[ConvWidth,ConvWidth]->A
function C.convolveConstant( A, ConvWidth, tab, shift, X )
  assert(type(shift)=="number")
  assert(X==nil)

  local inp = d.input( types.array2d( A, ConvWidth, ConvWidth ) )
  local r = d.constant( "convkernel", tab, types.array2d( A, ConvWidth, ConvWidth) )

  local packed = d.apply( "packedtup", d.SoAtoAoS(ConvWidth,ConvWidth,{A,A}), d.tuple("ptup", {inp,r}) )
  local conv = d.apply( "partial", d.map( C.multiply(A,A,types.uint(32)), ConvWidth, ConvWidth ), packed )
  local conv = d.apply( "sum", d.reduce( C.sum(types.uint(32),types.uint(32),types.uint(32)), ConvWidth, ConvWidth ), conv )
  local conv = d.apply( "touint8", C.shiftAndCast( types.uint(32), A, shift ), conv )

  local convolve = d.lambda( "convolve", inp, conv )
  return convolve
end

------------
-- returns a function from A[2][Width,Width]->reduceType
-- 'reduceType' is the precision we do the sum
function C.SAD( A, reduceType, Width, X )
  assert(X==nil)

  local inp = d.input( types.array2d( types.array2d(A,2) , Width, Width ) )

  local conv = d.apply( "partial", d.map( C.absoluteDifference(A,reduceType), Width, Width ), inp )
  local conv = d.apply( "sum", d.reduce( C.sum(reduceType, reduceType, reduceType), Width, Width ), conv )

  local convolve = d.lambda( "SAD", inp, conv )
  return convolve
end

------------
-- takes a function f:A[StencilW,stencilH]->B
-- returns a function from A[T]->B[T]
function C.stencilKernel( A, T, imageW, imageH, stencilW, stencilH, f)
  local BASE_TYPE = types.array2d( A, T )
  local ITYPE = d.Stateful(BASE_TYPE)
  local inp = d.input( ITYPE )
  
  --I = d.apply("crop", d.cropSeq(types.uint(8),W,H,T,ConvWidth,0,ConvWidth,0,0), inp)
  local convLB = d.apply( "convLB", d.stencilLinebuffer( A, imageW, imageH, T, -stencilW+1, 0, -stencilH+1, 0 ), inp)
  local convstencils = d.apply( "convstencils", d.makeStateful( d.unpackStencil( A, stencilW, stencilH, T ) ), convLB )
  local convpipe = d.apply( "conv", d.makeStateful( d.map( f, T ) ), convstencils )
  
  local convpipe = d.lambda( "convpipe", inp, convpipe )
  return convpipe
end

------------
-- takes a function f:{A[StencilW,StencilH],tapType}->B
-- returns a function that goes from A[T]->B[T]. Applies f using a linebuffer
function C.stencilKernelTaps( A, T, tapType, imageW, imageH, stencilW, stencilH, f )
  assert(type(stencilW)=="number")
  assert(type(stencilH)=="number")

  local BASE_TYPE = types.array2d( A, T )
  local ITYPE_RAW = types.tuple{BASE_TYPE, tapType}
  local ITYPE = d.Stateful( ITYPE_RAW )
  local rawinp = d.input( ITYPE )
  
  local inp = d.apply("idx0",d.makeStateful(d.index(ITYPE_RAW,0)),rawinp)
  local taps = d.apply("idx1",d.makeStateful(d.index(ITYPE_RAW,1)),rawinp)
  
  local convLB = d.apply( "convLB", d.stencilLinebuffer( A, imageW, imageH, T, -stencilW+1, 0, -stencilH+1, 0 ), inp)
  local convstencils = d.apply( "convstencils", d.makeStateful( d.unpackStencil( A, stencilW, stencilH, T ) ), convLB )
  
  local st_tap_inp = d.apply( "broad", d.makeStateful(d.broadcast(tapType,T)), taps )
  st_tap_inp = d.tuple("sttapinp",{convstencils,st_tap_inp})
  local ST_TYPE = types.array2d( A, stencilW, stencilH )
  st_tap_inp = d.apply("ST",d.SoAtoAoSStateful(T,1,{ST_TYPE,tapType}),st_tap_inp)
  local convpipe = d.apply( "conv", d.makeStateful( d.map( f, T ) ), st_tap_inp )
  
  local convpipe = d.lambda( "convpipe", rawinp, convpipe )
  return convpipe
end
-------------
-- f should be a _lua_ function that takes two arguments, (internalW,internalH), and returns the 
-- inner function based on this W,H. We have to do this for alignment reasons.
-- f should return a handshake function
function C.padcrop(A,W,H,T,L,R,B,Top,borderValue,f,X)
  print("padcrop","W",W,"H",H,"T",T,"L",L,"R",R,"B",B,"Top",Top)
  assert(X==nil)

  local RW_TYPE = types.array2d( A, T ) -- simulate axi bus
  local hsfninp = d.input( d.StatefulHandshake(RW_TYPE) )
  --local out = hsfninp
  --local out = d.apply("reducerate", d.liftHandshake(d.changeRate(types.uint(8),8,T)), hsfninp )
  local internalL = upToNearest(T,L)
  local internalR = upToNearest(T,R)

--  local internalL,internalR=L,R
  local internalW, internalH = W+internalL+internalR,H+B+Top

  local out = d.apply("pad", d.liftHandshake(d.padSeq(A, W, H, T, internalL, internalR, B, Top, borderValue)), hsfninp)
  local out = d.apply("HH",f(internalW, internalH), out)
  local padL = internalL-L
  local padR = internalR-R
  local out = d.apply("crop",d.liftHandshake(d.liftDecimate(d.cropHelperSeq(A, internalW, internalH, T, padL+R+L, padR, B+Top, 0))), out)
  --local out = d.apply("incrate", d.liftHandshake(d.changeRate(types.uint(8),T,8)), out )
  local hsfn = d.lambda("hsfn", hsfninp, out)
  return hsfn
end

-------------
return C