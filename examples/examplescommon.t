local d = require "darkroom"
local cstdlib = terralib.includec("stdlib.h")
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
  local a1 = S.index(sinp,1)
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

  local partial = d.lift( "absoluteDifference", TY, outputType, 1,
                          terra( a : &(A:toTerraType())[2], out : &outputType:toTerraType() )
                            @out = [outputType:toTerraType()](cstdlib.abs([internalType_terra]((@a)[0])-[internalType_terra]((@a)[1])) )
                          end, sinp, out )
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


function C.SADFixed( A, reduceType, Width, X )
  local fixed = require "fixed"
  assert(X==nil)
  fixed.expectFixed(reduceType)
  assert(fixed.extractSigned(reduceType)==false)
  assert(fixed.extractExp(reduceType)==0)

  local inp = d.input( types.array2d( types.array2d(A,2) , Width, Width ) )

  -------
  local ABS_inp = fixed.parameter("abs_inp", types.array2d(A,2))
  local ABS_l, ABS_r = ABS_inp:index(0):lift(0):toSigned(), ABS_inp:index(1):lift(0):toSigned()
  local ABS = (ABS_l-ABS_r):abs():pad(fixed.extractPrecision(reduceType),0)
  ------
  local SUM_inp = fixed.parameter("sum_inp", types.tuple{reduceType,reduceType})
  local SUM_l, SUM_r = SUM_inp:index(0), SUM_inp:index(1)
  local SUM = (SUM_l+SUM_r)

  SUM = SUM:truncate(fixed.extractPrecision(reduceType))

--  SUM = SUM:normalize(fixed.extractPrecision(reduceType))
--  SUM = SUM:truncate(fixed.extractPrecision(reduceType))
--  SUM = SUM:lower(true):lift(0)

  ------

  local conv = d.apply( "partial", d.map( ABS:toDarkroom("absoluteDiff"), Width, Width ), inp )
  local conv = d.apply( "sum", d.reduce( SUM:toDarkroom("ABS_SUM"), Width, Width ), conv )

  local convolve = d.lambda( "SAD", inp, conv )
  return convolve
end

------------
-- takes a function f:A[StencilW,stencilH]->B
-- returns a function from A[T]->B[T]
function C.stencilKernel( A, T, imageW, imageH, stencilW, stencilH, f)
  local BASE_TYPE = types.array2d( A, T )
  local inp = d.input( BASE_TYPE )
  
  --I = d.apply("crop", d.cropSeq(types.uint(8),W,H,T,ConvWidth,0,ConvWidth,0,0), inp)
  local convLB = d.apply( "convLB", d.stencilLinebuffer( A, imageW, imageH, T, -stencilW+1, 0, -stencilH+1, 0 ), inp)
  local convstencils = d.apply( "convstencils", d.unpackStencil( A, stencilW, stencilH, T ), convLB )
  local convpipe = d.apply( "conv", d.map( f, T ), convstencils )
  
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
  local ITYPE = types.tuple{BASE_TYPE, tapType}
  local rawinp = d.input( ITYPE )
  
  local inp = d.apply("idx0",d.index(ITYPE,0),rawinp)
  local taps = d.apply("idx1",d.index(ITYPE,1),rawinp)
  
  local convLB = d.apply( "convLB", d.stencilLinebuffer( A, imageW, imageH, T, -stencilW+1, 0, -stencilH+1, 0 ), inp)
  local convstencils = d.apply( "convstencils", d.unpackStencil( A, stencilW, stencilH, T ) , convLB )
  
  local st_tap_inp = d.apply( "broad", d.broadcast(tapType,T), taps )
  st_tap_inp = d.tuple("sttapinp",{convstencils,st_tap_inp})
  local ST_TYPE = types.array2d( A, stencilW, stencilH )
  st_tap_inp = d.apply("ST",d.SoAtoAoS(T,1,{ST_TYPE,tapType}),st_tap_inp)
  local convpipe = d.apply( "conv", d.map( f, T ), st_tap_inp )
  
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
  local hsfninp = d.input( d.Handshake(RW_TYPE) )
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
  local inp = d.input(ITYPE)
  local sinp = S.parameter("sinp",types.uint(totalbits))
--  local sout = S.bitSlice(sinp,0,7)
  local sout = S.cast(sinp,types.uint(totalbits-1))
  return darkroom.lift("stripMSB",ITYPE,types.uint(totalbits-1),0,
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

  local inp = d.input( ty )
  local aout = d.apply( "a", afn, inp )
  local aout_float = d.apply("aout_float", d.index(afn.outputType,0), aout)
  local aout_exp = d.apply("aout_exp", d.index(afn.outputType,1), aout)
  local aout_sign
  if signed then aout_sign = d.apply("aout_sign", d.index(afn.outputType,2), aout) end

  local aout_float_lsbs = d.apply("aout_float_lsbs", stripMSB(9), aout_float)

  local inv = d.apply("inv", d.lut(types.uint(lutbits), types.uint(8), invtable(lutbits)), aout_float_lsbs)
  local out = d.apply( "b", bfn, d.tuple("binp",{inv,aout_exp,aout_sign}) )
  local fn = d.lambda( "lutinvert", inp, out )

  return fn, fn.outputType
end

-------------
return C