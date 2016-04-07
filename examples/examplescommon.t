local R = require "rigel"
local RM = require "modules"
local cstdlib = terralib.includec("stdlib.h")
local C = {}

C.identity = memoize(function(A)
  local sinp = S.parameter( "inp", A )
  local identity = RM.lift( "identity_"..tostring(A), A, A, 0,
                          terra( a : &A:toTerraType(), out : &A:toTerraType() )
                            @out = @a
                  end, sinp, sinp )
  return identity
                     end)

C.cast = memoize(function(A,B)
                   assert(A:isTuple()==false)

  local sinp = S.parameter( "inp", A )
  local docast = RM.lift( "cast_"..tostring(A).."_"..tostring(B), A, B, 0,
                          terra( a : &A:toTerraType(), out : &B:toTerraType() )
                            @out = [B:toTerraType()](@a)
                  end, sinp, S.cast(sinp,B) )
  return docast
end)

C.tupleToArray = memoize(function(A,N)
                           local atup = types.tuple(rep(A,N))
                           local B = types.array2d(A,N)

  local sinp = S.parameter( "inp", atup )
  local docast = RM.lift( "tupleToArray_"..tostring(A).."_"..tostring(N), atup, B, 0,
                          terra( a : &atup:toTerraType(), out : &B:toTerraType() )
                            escape
                            for i=0,N-1 do
                              emit quote (@out)[i] = a.["_"..i] end
                            end
                          end
                  end, sinp, S.cast(sinp,B) )
return docast
                         end)
-- A -> A[W,H]
C.arrayop = memoize(function(A,W,H)
  local inp = R.input(A)
  return RM.lambda("arrayop_"..tostring(A).."_W"..W.."_H"..tostring(H),inp,R.array2d("ao",{inp},W,H))
end)

------------
-- return A*B as a darkroom FN. A,B are types
-- returns something of type outputType
C.multiply = memoize(function(A,B,outputType)
  local sinp = S.parameter( "inp", types.tuple {A,B} )
  local partial = RM.lift( "partial_mult_A"..(tostring(A):gsub('%W','_')).."_B"..(tostring(B):gsub('%W','_')), types.tuple {A,B}, outputType, 1,
                          terra( a : &tuple(A:toTerraType(),B:toTerraType()), out : &outputType:toTerraType() )
                            @out = [outputType:toTerraType()](a._0)*[outputType:toTerraType()](a._1)
                  end, sinp, S.cast(S.index(sinp,0),outputType)*S.cast(S.index(sinp,1),outputType) )
  return partial
                     end)
------------
-- return A+B as a darkroom FN. A,B are types
-- returns something of type outputType
C.sum = memoize(function(A,B,outputType,async)
                  if async==nil then async=false end

  local sinp = S.parameter( "inp", types.tuple {A,B} )
  local delay = 1
  local sout = S.cast(S.index(sinp,0),outputType)+S.cast(S.index(sinp,1),outputType)
  if async then delay=0; sout = sout:disablePipelining() end
  local partial = RM.lift( "sum_async"..tostring(async), types.tuple {A,B}, outputType, delay,
                          terra( a : &tuple(A:toTerraType(),B:toTerraType()), out : &outputType:toTerraType() )
                            @out = [outputType:toTerraType()](a._0)+[outputType:toTerraType()](a._1)
                  end, sinp, sout )
  return partial
                end)

-------------
-- {{idxType,vType},{idxType,vType}} -> {idxType,vType}
-- async: 0 cycle delay
function C.argmin(idxType,vType, async)
  local ATYPE = types.tuple {idxType,vType}
  local ITYPE = types.tuple{ATYPE,ATYPE}
  local sinp = S.parameter( "inp", ITYPE )

  local a0 = S.index(sinp,0)
  local a0v = S.index(a0,1)
  local a1 = S.index(sinp,1)
  local a1v = S.index(a1,1)

  local delay = 2
  local out = S.select(S.le(a0v,a1v),a0,a1)

  if async==true then 
    out = out:disablePipelining() 
    delay = 0
  end

  local partial = RM.lift( "argmin_async"..tostring(async), ITYPE, ATYPE, delay,
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
-- this returns a function from A[2]->A
-- return |A[0]-A[1]| as a darkroom FN. 
-- The largest absolute difference possible is the max value of A - min value, so returning type A is always fine.
-- we fuse this with a cast to 'outputType' just for convenience.
function C.absoluteDifference(A,outputType,X)
  assert(types.isType(A))
  assert(types.isType(outputType))
  assert(X==nil)

  local TY = types.array2d(A,2)
  local sinp = S.parameter( "inp", TY )
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

  local subabs = S.abs(S.cast(S.index(sinp,0),internalType)-S.cast(S.index(sinp,1),internalType))
  local out = S.cast(subabs, internalType_uint)
  local out = S.cast(out, outputType)

  local partial = RM.lift( "absoluteDifference", TY, outputType, 1,
                          terra( a : &(A:toTerraType())[2], out : &outputType:toTerraType() )
                            @out = [outputType:toTerraType()](cstdlib.abs([internalType_terra]((@a)[0])-[internalType_terra]((@a)[1])) )
                          end, sinp, out )
  return partial
end

------------
-- returns a darkroom FN that casts type 'from' to type 'to'
-- performs [to](from >> shift)
C.shiftAndCast = memoize(function(from, to, shift)
  local touint8inp = S.parameter("inp", from)
  local touint8 = RM.lift( "touint8", from, to, 1, terra( a : &from:toTerraType(), out : &to:toTerraType() ) @out = [uint8](@a >> shift) end, touint8inp, S.cast(S.rshift(touint8inp,S.constant(shift,from)), to) )
  return touint8
                         end)

C.shiftAndCastSaturate = memoize(function(from, to, shift)
  local touint8inp = S.parameter("inp", from)
  local OT = S.rshift(touint8inp,S.constant(shift,from))
  local touint8 = RM.lift( "touint8", from, to, 1, terra( a : &from:toTerraType(), out : &to:toTerraType() ) @out = [uint8](@a >> shift) end, touint8inp, S.select(S.gt(OT,S.constant(255,from)),S.constant(255,types.uint(8)), S.cast(OT,to)) )
  return touint8
                         end)

-------------
-- returns a function of type {A[ConvWidth,ConvWidth], A_const[ConvWidth,ConvWidth]}
-- that convolves the two arrays
function C.convolveTaps( A, ConvWidth, shift )
  if shift==nil then shift=7 end

  local TAP_TYPE = types.array2d( A, ConvWidth, ConvWidth )
  local TAP_TYPE_CONST = TAP_TYPE:makeConst()

  local INP_TYPE = types.tuple{types.array2d( A, ConvWidth, ConvWidth ),TAP_TYPE_CONST}
  local inp = R.input( INP_TYPE )

  local packed = R.apply( "packedtup", RM.SoAtoAoS(ConvWidth,ConvWidth,{A,A:makeConst()}), inp )
  local conv = R.apply( "partial", RM.map( C.multiply(A,A:makeConst(), types.uint(32)), ConvWidth, ConvWidth ), packed )
  local conv = R.apply( "sum", RM.reduce( C.sum(types.uint(32),types.uint(32),types.uint(32)), ConvWidth, ConvWidth ), conv )
  local conv = R.apply( "touint8", C.shiftAndCast(types.uint(32),A,shift), conv )

  local convolve = RM.lambda( "convolveTaps", inp, conv )
  return convolve
end

------------
-- returns a function from A[ConvWidth,ConvHeight]->A
function C.convolveConstant( A, ConvWidth, ConvHeight, tab, shift, X )
  assert(type(ConvWidth)=="number")
  assert(type(ConvHeight)=="number")
  assert(type(tab)=="table")
  assert(type(shift)=="number")
  assert(X==nil)

  local inp = R.input( types.array2d( A, ConvWidth, ConvHeight ) )
  local r = R.constant( "convkernel", tab, types.array2d( A, ConvWidth, ConvHeight) )

  local packed = R.apply( "packedtup", RM.SoAtoAoS(ConvWidth,ConvHeight,{A,A}), R.tuple("ptup", {inp,r}) )
  local conv = R.apply( "partial", RM.map( C.multiply(A,A,types.uint(32)), ConvWidth, ConvHeight ), packed )
  local conv = R.apply( "sum", RM.reduce( C.sum(types.uint(32),types.uint(32),types.uint(32)), ConvWidth, ConvHeight ), conv )
  local conv = R.apply( "touint8", C.shiftAndCast( types.uint(32), A, shift ), conv )

  local convolve = RM.lambda( "convolveConstant_W"..tostring(ConvWidth).."_H"..tostring(ConvHeight), inp, conv )
  return convolve
end

------------
-- returns a function from A[ConvWidth*T,ConvWidth]->A, with throughput T
function C.convolveConstantTR( A, ConvWidth, ConvHeight, T, tab, shift, X )
  assert(type(shift)=="number")
  assert(type(T)=="number")
  assert(T<=1)
  assert(type(shift)=="number")
  assert(X==nil)

  local inp = R.input( types.array2d( A, ConvWidth*T, ConvHeight ) )
  local r = R.apply( "convKernel", RM.constSeq( tab, A, ConvWidth, ConvHeight, T ) )

  local packed = R.apply( "packedtup", RM.SoAtoAoS(ConvWidth*T,ConvHeight,{A,A}), R.tuple("ptup", {inp,r}) )
  local conv = R.apply( "partial", RM.map( C.multiply(A,A,types.uint(32)), ConvWidth*T, ConvHeight ), packed )
  local conv = R.apply( "sum", RM.reduce( C.sum(types.uint(32),types.uint(32),types.uint(32)), ConvWidth*T, ConvHeight ), conv )

  local convseq = RM.lambda( "convseq_T"..tostring(1/T), inp, conv )
------------------
  inp = R.input( R.V(types.array2d( A, ConvWidth*T, ConvHeight )) )
  conv = R.apply( "convseqapply", RM.liftDecimate(RM.liftBasic(convseq)), inp)
  conv = R.apply( "sumseq", RM.RPassthrough(RM.liftDecimate(RM.reduceSeq( C.sum(types.uint(32),types.uint(32),types.uint(32),true), T ))), conv )
  conv = R.apply( "touint8", RM.RVPassthrough(C.shiftAndCast( types.uint(32), A, shift )), conv )
  conv = R.apply( "arrayop", RM.RVPassthrough(C.arrayop( types.uint(8), 1, 1)), conv)

  local convolve = RM.lambda( "convolve_tr_T"..tostring(1/T), inp, conv )

  return convolve
end

------------
-- returns a function from A[2][Width,Width]->reduceType
-- 'reduceType' is the precision we do the sum
function C.SAD( A, reduceType, Width, X )
  assert(X==nil)

  local inp = R.input( types.array2d( types.array2d(A,2) , Width, Width ) )

  local conv = R.apply( "partial", RM.map( C.absoluteDifference(A,reduceType), Width, Width ), inp )
  local conv = R.apply( "sum", RM.reduce( C.sum(reduceType, reduceType, reduceType), Width, Width ), conv )

  local convolve = RM.lambda( "SAD", inp, conv )
  return convolve
end


function C.SADFixed( A, reduceType, Width, X )
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

  local conv = R.apply( "partial", RM.map( ABS:toDarkroom("absoluteDiff"), Width, Width ), inp )
  local conv = R.apply( "sum", RM.reduce( SUM:toDarkroom("ABS_SUM"), Width, Width ), conv )

  local convolve = RM.lambda( "SAD", inp, conv )
  return convolve
end


function C.SADFixed4( A, reduceType, Width, X )
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

  local conv = R.apply( "partial", RM.map( ABS:toDarkroom("absoluteDiff"), Width, Width ), inp )
  local conv = R.apply( "sum", RM.reduce( SUM:toDarkroom("ABS_SUM"), Width, Width ), conv )

  local convolve = RM.lambda( "SAD", inp, conv )
  return convolve
end

------------
-- takes a function f:A[StencilW,stencilH]->B
-- returns a function from A[T]->B[T]
function C.stencilKernel( A, T, imageW, imageH, stencilW, stencilH, f)
  local BASE_TYPE = types.array2d( A, T )
  local inp = R.input( BASE_TYPE )
  
  local convLB = R.apply( "convLB", RM.stencilLinebuffer( A, imageW, imageH, T, -stencilW+1, 0, -stencilH+1, 0 ), inp)
  local convstencils = R.apply( "convstencils", RM.unpackStencil( A, stencilW, stencilH, T ), convLB )
  local convpipe = R.apply( "conv", RM.map( f, T ), convstencils )
  
  local convpipe = RM.lambda( "convpipe_"..f.kind.."_W"..tostring(stencilW).."_H"..tostring(stencilH), inp, convpipe )
  return convpipe
end

------------
-- takes a function f:{A[StencilW,StencilH],tapType}->B
-- returns a function that goes from A[T]->B[T]. Applies f using a linebuffer
function C.stencilKernelTaps( A, T, tapType, imageW, imageH, stencilW, stencilH, f )
  assert(type(stencilW)=="number")
  assert(type(stencilH)=="number")

  local BASE_TYPE = types.array2d( A, T )
  local ITYPE = types.tuple{BASE_TYPE, tapType}
  local rawinp = R.input( ITYPE )
  
  local inp = R.apply("idx0",RM.index(ITYPE,0),rawinp)
  local taps = R.apply("idx1",RM.index(ITYPE,1),rawinp)
  
  local convLB = R.apply( "convLB", RM.stencilLinebuffer( A, imageW, imageH, T, -stencilW+1, 0, -stencilH+1, 0 ), inp)
  local convstencils = R.apply( "convstencils", RM.unpackStencil( A, stencilW, stencilH, T ) , convLB )
  
  local st_tap_inp = R.apply( "broad", RM.broadcast(tapType,T), taps )
  st_tap_inp = R.tuple("sttapinp",{convstencils,st_tap_inp})
  local ST_TYPE = types.array2d( A, stencilW, stencilH )
  st_tap_inp = R.apply("ST",RM.SoAtoAoS(T,1,{ST_TYPE,tapType}),st_tap_inp)
  local convpipe = R.apply( "conv", RM.map( f, T ), st_tap_inp )
  
  local convpipe = RM.lambda( "convpipe", rawinp, convpipe )
  return convpipe
end
-------------
-- f should be a _lua_ function that takes two arguments, (internalW,internalH), and returns the 
-- inner function based on this W,H. We have to do this for alignment reasons.
-- f should return a handshake function
-- timingFifo: include a fifo to improve timing. true by default
function C.padcrop(A,W,H,T,L,Right,B,Top,borderValue,f,timingFifo,X)
  print("padcrop","W",W,"H",H,"T",T,"L",L,"R",Right,"B",B,"Top",Top)
  assert(X==nil)
  assert(timingFifo==nil or type(timingFifo)=="boolean")
  if timingFifo==nil then timingFifo=true end

  local RW_TYPE = types.array2d( A, T ) -- simulate axi bus
  local hsfninp = R.input( R.Handshake(RW_TYPE) )

  local internalL = upToNearest(T,L)
  local internalR = upToNearest(T,Right)

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
  local out = R.apply("crop",RM.liftHandshake(RM.liftDecimate(RM.cropHelperSeq(fnOutType, internalW, internalH, T, padL+Right+L, padR, B+Top, 0))), out)

  if timingFifo then
    -- this FIFO is only for improving timing
    table.insert( fifos, R.instantiateRegistered("f2",RM.fifo(types.array2d(fnOutType,T),128)) )
    table.insert( statements, R.applyMethod("s2",fifos[#fifos],"store",out) )
    out = R.applyMethod("l2",fifos[#fifos],"load")
  end
  -----------------

  table.insert(statements,1,out)

  local name = "hsfn_"..tostring(A):gsub('%W','_').."L"..tostring(L).."_R"..tostring(Right).."_B"..tostring(B).."_T"..tostring(Top).."_W"..tostring(W).."_H"..tostring(H)..tostring(f)

  local hsfn
  if timingFifo then
    hsfn = RM.lambda(name, hsfninp, R.statements(statements), fifos )
  else
    hsfn = RM.lambda(name, hsfninp, out)
  end

  return hsfn
end

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
  local terra inv(a:uint32) 
    if a==0 then 
      return 0 
    else
      var o = ([math.pow(2,17)]/([uint32](255)+a))-[uint32](256)
      if o>255 then return 255 end
      return o
    end 
  end

  local function round(x) if (x%1>=0.5) then return math.ceil(x) else return math.floor(x) end end

  for i=0,math.pow(2,bits)-1 do 
    --local v = inv(i)
    --
    local v = (math.pow(2,17)/(256+i)) - 256
    if v>255 then v = 255 end
    v = round(v)
    print("LUT ",i,v)
    table.insert(out, v) 
  end
  return out
end

function stripMSB(totalbits)
  local ITYPE = types.uint(totalbits)
  local inp = R.input(ITYPE)
  local sinp = S.parameter("sinp",types.uint(totalbits))
--  local sout = S.bitSlice(sinp,0,7)
  local sout = S.cast(sinp,types.uint(totalbits-1))
  return RM.lift("stripMSB",ITYPE,types.uint(totalbits-1),0,
                       terra(inp:&uint16, out:&uint8)
--                         @out = @inp
                         var ot : uint8 = @inp
--                         cstdio.printf("stripmsb %d to %d\n",@inp,ot)
                         @out = ot
                       end,sinp,sout)
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
  local afn = aout:toDarkroom("lutinvert_a")
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
  local bfn = b:toDarkroom("lutinvert_b")
  ---------------

  local inp = R.input( ty )
  local aout = R.apply( "a", afn, inp )
  local aout_float = R.apply("aout_float", RM.index(afn.outputType,0), aout)
  local aout_exp = R.apply("aout_exp", RM.index(afn.outputType,1), aout)
  local aout_sign
  if signed then aout_sign = R.apply("aout_sign", RM.index(afn.outputType,2), aout) end

  local aout_float_lsbs = R.apply("aout_float_lsbs", stripMSB(9), aout_float)

  local inv = R.apply("inv", RM.lut(types.uint(lutbits), types.uint(8), invtable(lutbits)), aout_float_lsbs)
  local out = R.apply( "b", bfn, R.tuple("binp",{inv,aout_exp,aout_sign}) )
  local fn = RM.lambda( "lutinvert", inp, out )

  return fn, fn.outputType
end
-------------
C.stencilLinebufferPartialOffsetOverlap = memoize(function( A, w, h, T, xmin, xmax, ymin, ymax, offset, overlap )
  map({T,w,h,xmin,xmax,ymin,ymax}, function(i) assert(type(i)=="number") end)
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
  out = R.apply("slice", RM.makeHandshake(RM.slice(types.array2d(A,ST_W,-ymin+1), 0, stride+overlap-1, 0,-ymin)), out)

  return RM.lambda("stencilLinebufferPartialOverlap",inp,out)
                                                  end)

-------------
function C.fifo(fifos,statements,A,inp,size,name, csimOnly, X)
  assert(type(name)=="string")
  assert(X==nil)

  table.insert( fifos, R.instantiateRegistered(name, RM.fifo(A,size,nil,nil,nil,nil,csimOnly)) )
  table.insert( statements, R.applyMethod("s"..tostring(#fifos),fifos[#fifos],"store",inp) )
  return R.applyMethod("l"..tostring(#fifos),fifos[#fifos],"load")
end
-------------



return C