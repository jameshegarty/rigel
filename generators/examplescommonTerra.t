local cstdlib = terralib.includec("stdlib.h", {"-Wno-nullability-completeness"})
local cstdio = terralib.includec("stdio.h",{"-Wno-nullability-completeness"})
local cstring = terralib.includec("string.h",{"-Wno-nullability-completeness"})
local cmath = terralib.includec("math.h", {"-Wno-nullability-completeness"})
local rigel = require "rigel"
local types = require "types"
local J = require "common"
local err = J.err
local MT = require "generators.modulesTerra"
local Uniform = require "uniform"

local data = macro(function(i) return `i._0 end)
local valid = macro(function(i) return `i._1 end)
local ready = macro(function(i) return `i._2 end)

CT={}

function CT.identity(A)
  return terra( a : &A:lower():toTerraType(), out : &A:lower():toTerraType() )
    @out = @a
  end
end

function CT.fassert( res, filename, ty, X )
  assert(rigel.isFunction(res))
  assert(X==nil)
  assert(ty:verilogBits()%8==0)
  assert(ty:verilogBits()==ty:sizeof()*8)
  local struct Fassert { file : &cstdio.FILE, token:uint }
  terra Fassert:init() 
    self.file = cstdio.fopen(filename, "rb") 
    [J.darkroomAssert](self.file~=nil, ["file "..filename.." doesnt exist"])
  end
  terra Fassert:reset() self.token=0 end
  terra Fassert:free() cstdio.fclose(self.file) end
  terra Fassert:process(inp : &ty:toTerraType(), out : &ty:toTerraType())
    var outBytes = cstdio.fread(out,1,[ty:sizeof()],self.file)
    [J.darkroomAssert](outBytes==[ty:sizeof()], "Error, freadSeq failed, probably end of file?")

    if @inp~=@out then
      cstdio.printf("Fassert: file and input don't match!!\n")
      cstdio.printf("input: %d/%#x\n",@inp,@inp)
      cstdio.printf("file: %d/%#x\n",@out,@out)
      cstdio.printf("at token number: %d, byte: %d\n",self.token,self.token*[ty:sizeof()])
      cstdlib.exit(1)
    end
    self.token = self.token+1
  end

  return MT.new( Fassert, res )
end

function CT.print( res, A, str, X )
  assert(rigel.isFunction(res))
  err(types.isBasic(A),"CT.print: type should be basic, but is: "..tostring(A) )
  assert(X==nil)
  
  local printS = quote end
  if str~=nil then printS = quote cstdio.printf("%s ",str) end  end

  local struct PrintModule {count:uint}
  terra PrintModule:process( a : &A:toTerraType(), out : &A:toTerraType() )
    var aa = @a
    printS
    cstdio.printf("(firing:%d) ",self.count)
    self.count = self.count+1
    [A:terraPrint(a)]
    cstdio.printf("\n")
    @out = @a
  end

  terra PrintModule:reset()
    self.count = 0
  end

  return MT.new( PrintModule, res )
end

function CT.cast(A,B)
  err(types.isType(B), "examples common cast, B must be type")
  
  if A:isBits() then
    return terra( a : &A:toTerraType(), out : &B:toTerraType() )
      @out = @[&B:toTerraType()](a)
    end
  elseif B:isBits() and A:isArray() and B:verilogBits()==A:verilogBits() then
    return terra( a : &A:toTerraType(), out : &B:toTerraType() )
      @out = @[&B:toTerraType()](a)
    end
  else
    return terra( a : &A:toTerraType(), out : &B:toTerraType() )
      @out = [B:toTerraType()](@a)
    end
  end
end

function CT.bitcast(A,B)
  err( terralib.sizeof(A:toTerraType()) <= terralib.sizeof(B:toTerraType()), "could not terra bitcast "..tostring(A).." (terra type: "..tostring(A:toTerraType())..") to "..tostring(B).." (terra type: "..tostring(B:toTerraType())..") because size shrunk?" )
  
  return terra( a : &A:toTerraType(), out : &B:toTerraType() )
    --@out = @[&B:toTerraType()](a)
    cstring.memcpy(out,a,[A:sizeof()])
  end
end

function CT.flatten2(T,N)
  local A = types.tuple{types.array2d(T,N/2),types.array2d(T,N/2)}
  local B = types.array2d(T,N)

  return terra( a : &A:toTerraType(), out : &B:toTerraType() )
    for i=0,N/2 do
      (@out)[i] = ((@a)._0)[i]
      (@out)[i+(N/2)] = ((@a)._1)[i]
    end
  end
end

function CT.tupleToArray(A,W,H,atup,B,X)
  assert(X==nil)
  
  return terra( a : &atup:toTerraType(), out : &B:toTerraType() )
                            escape
                            for i=0,(W*H)-1 do
                              emit quote (@out)[i] = a.["_"..i] end
                            end
                          end
                  end
end


function CT.multiply(A,B,outputType)
  return terra( a : &tuple(A:toTerraType(),B:toTerraType()), out : &outputType:toTerraType() )
                            @out = [outputType:toTerraType()](a._0)*[outputType:toTerraType()](a._1)
                  end
end

function CT.multiplyConst( A, constValue, outputType, X )
  assert( X==nil )
  return terra( a : &A:toTerraType(), out : &outputType:toTerraType() )
    @out = [outputType:toTerraType()](@a)*[outputType:toTerraType()](constValue)
  end
end

function CT.tokenCounter( res, A, str, X )
  assert( rigel.isFunction(res) )
  assert(X==nil)
  
  if str==nil then str="" end
  assert(type(str)=="string")
  
  local struct TokenCounter { cnt:uint, ready:bool }
  terra TokenCounter:reset() self.cnt=0 end
  terra TokenCounter:process( a : &A:lower():toTerraType(), out : &A:lower():toTerraType() )
    @out = @a

    if valid(a) and self.ready then
      self.cnt = self.cnt+1
      cstdio.printf(["CNT "..str..": %d\n"],self.cnt)
    end
  end

  terra TokenCounter:calculateReady(readyDownstream:bool)
    self.ready = readyDownstream
  end

  return MT.new( TokenCounter, res )
end

  local function trunc(inp,outputType)
    if outputType:verilogBits()==outputType:sizeof()*8 then
      -- operating at same bitwidth in terra: nothing to do
      return inp
    elseif outputType:isInt() then
      return quote
            var mask = ([outputType:toTerraType()](1) << [outputType:verilogBits()]) - 1
            var msb = [outputType:toTerraType()](1) << ([outputType:verilogBits()]-1)
            var notmask = not mask

            var inpuint = [outputType:toTerraType()]([inp])
            var masked = inpuint and mask

            -- extend the sign bit so that the CPU thinks this number has the correct sign
            -- note that we set the sign bit based on the MSB of the _masked_ portion. This is what verilog will do.
            -- DO NOT set sign bit based on sign bit of (unmaked) input.
            if (masked and msb) ~=0 then
              masked = masked or notmask
            end

            var r = [outputType:toTerraType()](masked)
            in r end
    elseif outputType:isUint() then
      return quote
            var mask = ([outputType:toTerraType()](1) << [outputType:verilogBits()]) - 1
            var r = [outputType:toTerraType()]([inp] and mask)
            in r end
    else
      assert(false)
    end
  end

function CT.sum(A,B,outputType,async)
  
  return terra( a : &tuple(A:toTerraType(),B:toTerraType()), out : &outputType:toTerraType() )
    @out = [outputType:toTerraType()](a._0)+[outputType:toTerraType()](a._1)
    @out = [trunc(`@out,outputType)]
  end
end

function CT.removeMSBs( A, bits, otype )
  return terra( a : &A:toTerraType(), out : &otype:toTerraType() )
    @out = [trunc(`@a,otype)]
  end
end

function CT.removeLSBs( A, bits, otype )
  return terra( a : &A:toTerraType(), out : &otype:toTerraType() )
    var tmp = @a >> bits
    @out = [otype:toTerraType()](tmp)
  end
end

function CT.argmin(ITYPE,ATYPE,domax)
  if domax then
    return terra( a : &ITYPE:toTerraType(), out : &ATYPE:toTerraType() )
      if a._0._1 >= a._1._1 then @out = a._0 else @out = a._1 end
    end
  else
    return terra( a : &ITYPE:toTerraType(), out : &ATYPE:toTerraType() )
      if a._0._1 <= a._1._1 then @out = a._0 else @out = a._1 end
    end
  end
end

function CT.absoluteDifference(A,outputType,internalType_terra)
  return terra( a : &(A:toTerraType())[2], out : &outputType:toTerraType() )
                            @out = [outputType:toTerraType()](cstdlib.abs([internalType_terra]((@a)[0])-[internalType_terra]((@a)[1])) )
                          end
end

function CT.shiftAndCast(from, to, shift)
  return terra( a : &from:toTerraType(), out : &to:toTerraType() ) @out = [uint8](@a >> shift) end
end

function CT.shiftAndCastSaturate(from,to,shift)
  return terra( a : &from:toTerraType(), out : &to:toTerraType() ) @out = [uint8](@a >> shift) end
end

function CT.border( res, A,W,H,L,R,B,T,value)
  local struct Border {}

  terra Border:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    for y=0,H do for x=0,W do 
        if x<L or y<B or x>=W-R or y>=H-T then
          (@out)[y*W+x] = [value]
        else
          (@out)[y*W+x] = (@inp)[y*W+x]
        end
    end end
  end

  return MT.new( Border, res )
end

function CT.scale( res, A, w, h, scaleX, scaleY )
  local struct ScaleModule {}

  terra ScaleModule:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    for y=0,[h*scaleY] do 
      for x=0,[w*scaleX] do
        var idx = [int](cmath.floor([float](x)/[float](scaleX)))
        var idy = [int](cmath.floor([float](y)/[float](scaleY)))
--        cstdio.printf("SCALE outx %d outy %d, inx %d iny %d\n",x,y,idx,idy)
        (@out)[y*[w*scaleX]+x] = (@inp)[idy*w+idx]
      end
    end
  end

  return MT.new( ScaleModule, res )
end

function CT.broadcast(A,W,H,OT)
  return terra(inp : &A:toTerraType(), out:&OT:toTerraType() )
    for y=0,H do
      for x=0,W do (@out)[y*W+x] = @inp end
    end
	end
end

function CT.broadcastTuple( A, OT, N )
  return terra(inp : &A:lower():toTerraType(), out:&OT:lower():toTerraType() )
    escape
      for i=0,N-1 do
        emit quote (@out).["_"..i] = @inp end
      end
    end
  end
end

function CT.stencil( res, A, w, h, xmin, xmax, ymin, ymax )
  local struct Stencil {}

  terra Stencil:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    for i=0,[w*h] do
      for y = ymin, ymax+1 do
        for x = xmin, xmax+1 do
          var idx = i+x+y*w
          if idx>=0 and idx < w*h then -- prevent segfaults
            ((@out)[i])[(y-ymin)*(xmax-xmin+1)+(x-xmin)] = (@inp)[idx]
          end
        end
      end
    end
  end

  return MT.new( Stencil, res )
end

function CT.borderSeq( A, W, H, T, L, R, B, Top, Value, inpType )
  return terra( inp :&inpType:toTerraType(), out : &A:toTerraType() )
                             var x,y, inpvalue = inp._0._0, inp._0._1, inp._1
                                  if x<L or y<B or x>=W-R or y>=H-Top then @out = [Value]
                                  else @out = inpvalue end
                                end
end


function CT.unpackStencil(res, A, stencilW, stencilH, T, arrHeight)
  local struct UnpackStencil {}
  terra UnpackStencil:process( inp : &res.inputType:lower():toTerraType(), out : &res.outputType:lower():toTerraType() )
    for i=0,[T] do
      for y=0,[stencilH] do
        for x=0,[stencilW] do
          (@out)[i][y*stencilW+x] = (@inp)[y*(stencilW+T-1)+x+i]
        end
      end
    end
  end

  return MT.new( UnpackStencil, res )
end

function CT.sliceTup( inputType, OT, idxLow, idxHigh, index, X)
  assert( type(index)=="boolean" )
  assert( X==nil )
  if index then
    assert(idxLow==idxHigh)
    return terra( inp:&rigel.lower(inputType):toTerraType(), out:&rigel.lower(OT):toTerraType()) @out = inp.["_"..idxLow] end
  else
    local INP = symbol(&inputType:lower():toTerraType())

    local OUT = {}
    for i=idxLow,idxHigh do
      table.insert( OUT, `[INP].["_"..i] )
    end
    
    return terra( [INP], out:&OT:lower():toTerraType() )
    @out = {[OUT]}
    end
  end
end

function CT.sliceArr(inputType,OT,idxLow,idyLow,idxHigh,idyHigh,W)
  return terra(inp:&rigel.lower(inputType):toTerraType(), out:&rigel.lower(OT):toTerraType()) 
      for iy = idyLow,idyHigh+1 do
        for ix = idxLow, idxHigh+1 do
          (@out)[(iy-idyLow)*(idxHigh-idxLow+1)+(ix-idxLow)] = (@inp)[ix+iy*W] 
        end
      end
    end
end

function CT.sliceArrIdx(inputType,OT,idxLow,idyLow,idxHigh,idyHigh,W)
  return terra(inp:&rigel.lower(inputType):toTerraType(), out:&rigel.lower(OT):toTerraType()) @out = (@inp)[idxLow+idyLow*W] end
end

function CT.stripMSB(totalbits)
  return  terra(inp:&uint16, out:&uint8)
    var ot : uint8 = @inp
    @out = ot
  end
end

function CT.plusConsttfn( ty, value_orig, outputType, X)
  local value = Uniform(value_orig)
  
  local out = symbol(outputType:toTerraType(true))
  local q = quote end
  if ty:verilogBits()~=ty:sizeof()*8 then
    local valuen = value:toNumber()
    local vbits = math.ceil(math.log(valuen)/math.log(2))
    if outputType:verilogBits()>=math.max(vbits,ty:verilogBits())+1 then
      -- we know this has enough bits to not overflow, so no need to truncate...
    else
      q = quote @[out] = [trunc(`@[out],outputType)] end
    end
  end

  return terra( a : ty:toTerraType(true), [out] ) 
    @[out] =  [outputType:toTerraType()](@a)+[outputType:toTerraType()]([value:toTerra()]) 
    [q]
  end
end

function CT.subConsttfn( ty, value_orig, outputType, X)
  local value = Uniform(value_orig)
  
  local out = symbol(outputType:toTerraType(true))
  local q = quote end
  if ty:verilogBits()~=ty:sizeof()*8 then
    local valuen = value:toNumber()
    local vbits = math.ceil(math.log(valuen)/math.log(2))
    if outputType:verilogBits()>=math.max(vbits,ty:verilogBits())+1 then
      -- we know this has enough bits to not overflow, so no need to truncate...
    else
      q = quote @[out] = [trunc(`@[out],outputType)] end
    end
  end

print("SUBCONST",value_orig,ty,outputType)
  return terra( a : ty:toTerraType(true), [out] ) 
    @[out] =  [outputType:toTerraType()](@a)-[outputType:toTerraType()]([value:toTerra()]) 
    [q]
  end
end

function CT.denormalize(ty)
  if ty.exp<0 then
    -- throw out frac bits
    local outbits = ty.precision+ty.exp
    local outType = ty:replaceVar("precision",outbits):replaceVar("exp",0)

    print("CTDENORM",ty,outType)
    return terra( inp : &ty:toTerraType(), out : &outType:toTerraType() )
      var tmp = @inp >> [ty:toTerraType()]([math.max(0,-ty.exp)])
      @out = tmp
    end
  else
    assert(false)
  end
end

function CT.VRtoRVRaw( res, A, X )
  assert( rigel.isFunction(res) )
  assert( X==nil )
  err( types.isBasic(A), "expected basic type" )
  local struct VRtoRVRaw {ready:bool}

  terra VRtoRVRaw:process( inp:&rigel.lower(types.HandshakeVR(A)):toTerraType(), out:&rigel.lower(types.Handshake(A)):toTerraType())
    @out = @inp
  end

  terra VRtoRVRaw:calculateReady(readyDownstream:bool) self.ready = readyDownstream end
  return MT.new( VRtoRVRaw, res )
end

function CT.handshakeToHandshakeFramed(res,A,mixed,dims)
  local struct HandshakeToHandshakeFramed {ready:bool}
  terra HandshakeToHandshakeFramed:process( inp:&rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
    @out = @inp
  end
  terra HandshakeToHandshakeFramed:calculateReady(readyDownstream:bool) self.ready = readyDownstream end
  return MT.new(HandshakeToHandshakeFramed, res )
end

function CT.stripFramed(res,A)
  local struct StripFramed {ready:bool}
  terra StripFramed:process( inp:&rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
    @out = @inp
  end
  terra StripFramed:calculateReady(readyDownstream:bool) self.ready = readyDownstream end
  return MT.new(StripFramed, res )
end

function CT.generalizedChangeRate( res, inputBitsPerCyc, minTotalInputBits_orig, inputFactor, outputBitsPerCyc, minTotalOutputBits_orig, outputFactor, bts, X)
  assert( rigel.isFunction(res) )
  assert(inputBitsPerCyc%8==0)
  assert(outputBitsPerCyc%8==0)

  local inputType = rigel.Handshake(types.bits(inputBitsPerCyc))
  local outputType = rigel.Handshake(types.bits(outputBitsPerCyc))

  local shifterBits = J.lcm(inputBitsPerCyc,outputBitsPerCyc)
  assert(shifterBits%8==0)
  local shifterBytes = (shifterBits/8)
  local shifterBytesX2 = (shifterBits/8)*2 -- double the size, so that new writes don't overwrite reads in progress

  local inputBytesPerCyc = inputBitsPerCyc/8
  local outputBytesPerCyc = outputBitsPerCyc/8

  assert( (bts%inputFactor):eq(0):assertAlwaysTrue() )
  assert( (bts%outputFactor):eq(0):assertAlwaysTrue() )

  assert( (bts%shifterBits):eq(0):assertAlwaysTrue() )

  local struct GeneralizedChangeRate{ writePtr:int, readPtr:int, buf:uint8[shifterBytesX2], ready:bool, readyDownstream:bool}

  terra GeneralizedChangeRate:reset()
    self.writePtr=0
    self.readPtr=0
  end

  terra GeneralizedChangeRate:process( inp:&rigel.lower(inputType):toTerraType(), out:&rigel.lower(outputType):toTerraType())
--    cstdio.printf("GCR START inputBytesPerCyc:%d outputByteperCyc:%d writeptr:%d readptr:%d readyDS:%d ready:%d validIn:%d validOut:%d\n",inputBytesPerCyc,outputBytesPerCyc,self.writePtr,self.readPtr,self.readyDownstream,self.ready, valid(inp), valid(out))
--    [inputType:extractData():terraPrint(`&data(inp))]
--    cstdio.printf("\n")
    
    if valid(inp) and self.ready then
      cstring.memcpy(&self.buf[self.writePtr%shifterBytesX2],&data(inp),inputBytesPerCyc)
      self.writePtr = self.writePtr + inputBytesPerCyc
    end

    valid(out) = (self.writePtr-self.readPtr)>=outputBytesPerCyc
    cstring.memcpy( &data(out), &self.buf[self.readPtr%shifterBytesX2], outputBytesPerCyc )
    
    if valid(out) and self.readyDownstream then
      self.readPtr = self.readPtr + outputBytesPerCyc
    end

--    cstdio.printf("GCR END writeptr:%d readptr:%d readyDS:%d ready:%d validIn:%d validOut:%d\n",self.writePtr,self.readPtr,self.readyDownstream,self.ready, valid(inp), valid(out))

--    [outputType:extractData():terraPrint(`&data(out))]
--    cstdio.printf("\n")

  end

  terra GeneralizedChangeRate:calculateReady(readyDownstream:bool)
    self.readyDownstream = readyDownstream
    self.ready = readyDownstream and (self.writePtr-self.readPtr)<shifterBytes
  end
  return MT.new( GeneralizedChangeRate, res )

end

function CT.Float( res, exp, sig )
  assert( exp==8 )
  assert( sig==24 )
  local struct Float {}
  terra Float:process( inp:&rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
    @out = @inp
  end
  return MT.new( Float, res )
end

function CT.Sqrt( res, exp, sig, doDiv )
  assert( exp==8 )
  assert( sig==24 )
  local struct Sqrt { ready:bool; phase:int; buffer:float; bufferSet:bool, readyDownstream:bool }
  terra Sqrt:reset() self.phase=0; self.bufferSet=false end
  terra Sqrt:process( inp:&rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
    if self.phase>0 then
      self.phase = self.phase-1
    end

    if valid(inp) and self.ready then
      self.phase = [sig+3]
      escape
          if doDiv then
            emit quote self.buffer = data(inp)._0/data(inp)._1 end
          else
            emit quote self.buffer = cmath.sqrt(data(inp)) end
          end
      end

      self.bufferSet = true
    end
    
    valid(out) = self.bufferSet and (self.phase==0)
    data(out) = self.buffer

    if valid(out) and self.readyDownstream then
      self.bufferSet = false
    end
  end

  terra Sqrt:calculateReady( readyDownstream:bool ) 
    self.readyDownstream = readyDownstream
    self.ready = (self.phase==0) and readyDownstream
  end

  return MT.new( Sqrt, res )
end

function CT.FloatRec( res, inputType, exp, sig )
  assert( exp==8 )
  assert( sig==24 )
  local struct FloatRec {}
  terra FloatRec:process( inp:&rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
    @out = @inp
  end
  return MT.new( FloatRec, res )
end

function CT.FloatToFloatRec( res, exp, sig )
  assert( exp==8 )
  assert( sig==24 )
  local struct FloatToFloatRec {}
  terra FloatToFloatRec:process( inp:&rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
    @out = @inp
  end
  return MT.new( FloatToFloatRec, res )
end

function CT.FloatToInt( res, exp, sig, signed, intWidth )
  assert( exp==8 )
  assert( sig==24 )
  local struct FloatToInt {}
  terra FloatToInt:process( inp:&rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
    @out = @inp
  end
  return MT.new( FloatToInt, res )
end

function CT.SumF( res, exp, sig )
  assert( exp==8 )
  assert( sig==24 )
  local struct SumF {}
  terra SumF:process( inp:&rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
    @out = (@inp)._0 + (@inp)._1
  end
  return MT.new( SumF, res )
end

function CT.SubF( res, exp, sig )
  assert( exp==8 )
  assert( sig==24 )
  local struct SubF {}
  terra SubF:process( inp:&rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
    @out = (@inp)._0 - (@inp)._1
  end
  return MT.new( SubF, res )
end

function CT.MulF( res, exp, sig )
  assert( exp==8 )
  assert( sig==24 )
  local struct MulF {}
  terra MulF:process( inp:&rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
    @out = (@inp)._0 * (@inp)._1
  end
  return MT.new( MulF, res )
end

function CT.CMPF( res, exp, sig, op )
  assert( exp==8 )
  assert( sig==24 )
  local struct CMPF {}
  if op==">" then
    terra CMPF:process( inp:&rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
      @out = (@inp)._0 > (@inp)._1
    end
  elseif op==">=" then
    terra CMPF:process( inp:&rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
      @out = (@inp)._0 >= (@inp)._1
    end
  elseif op=="<" then
    terra CMPF:process( inp:&rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
      @out = (@inp)._0 < (@inp)._1
    end
  else
    assert(false)
  end

  return MT.new( CMPF, res )
end

function CT.flatten( res )
  local struct Flatten {ready:bool}

  assert( rigel.lower(res.inputType):sizeof() == rigel.lower(res.outputType):sizeof() )
  
  terra Flatten:process( inp:&rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
    @out = @([&rigel.lower(res.outputType):toTerraType()](inp))
  end

  terra Flatten:calculateReady( readyDownstream: bool )
    self.ready = readyDownstream
  end
  return MT.new( Flatten, res )
end

return CT
