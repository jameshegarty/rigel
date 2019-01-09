local cstdlib = terralib.includec("stdlib.h")
local cstdio = terralib.includec("stdio.h")
local rigel = require "rigel"
local types = require "types"
local J = require "common"
local err = J.err
local MT = require "modulesTerra"
local Uniform = require "uniform"

local data = macro(function(i) return `i._0 end)
local valid = macro(function(i) return `i._1 end)
local ready = macro(function(i) return `i._2 end)

CT={}

function CT.identity(A)
  return terra( a : &A:toTerraType(), out : &A:toTerraType() )
                            @out = @a
                  end
end

function CT.fassert(filename,ty)
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

  return MT.new(Fassert)
end

function CT.print(A,str)
  err(types.isBasic(A),"CT.print: type should be basic, but is: "..tostring(A) )
  
  local function doprint(A,symb)
    assert(symb~=nil)

    if A:isArray() then
      local tab = {}
      table.insert(tab,quote cstdio.printf("[") end)
      for i=0,A:channels()-1 do
        table.insert(tab,doprint(A:arrayOver(),`symb[i]))
        if i~=A:channels()-1 then table.insert(tab,quote cstdio.printf(",") end) end
      end
      table.insert(tab,quote cstdio.printf("]") end)
      return quote [tab] end
    elseif A:isTuple() then
      local tab = {}
      table.insert(tab,quote cstdio.printf("{") end)
      for i=1,#A.list do
        table.insert(tab,doprint(A.list[i],`symb.["_"..(i-1)]))
        if i~=#A.list then table.insert(tab,quote cstdio.printf(",") end) end
      end
      table.insert(tab,quote cstdio.printf("}") end)
      return quote [tab] end      
    elseif A:isUint() or A:isInt() or A:isBits() then
      return quote cstdio.printf("%d/%#x",symb,symb) end
    else
      print(A)
      assert(false)
    end
  end

  local printS = quote end
  if str~=nil then printS = quote cstdio.printf("%s ",str) end  end

  local struct PrintModule {count:uint}
  terra PrintModule:process( a : &A:toTerraType(), out : &A:toTerraType() )
    var aa = @a
    printS
    cstdio.printf("(firing:%d) ",self.count)
    self.count = self.count+1
    [doprint(A,aa)]
    cstdio.printf("\n")
    @out = @a
  end

  terra PrintModule:reset()
    self.count = 0
  end

  return MT.new(PrintModule)
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
  assert( terralib.sizeof(A:toTerraType()) == terralib.sizeof(B:toTerraType()) )
  return terra( a : &A:toTerraType(), out : &B:toTerraType() )
    @out = @[&B:toTerraType()](a)
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

function CT.multiplyConst(A,constValue)
  return terra( a : &A:toTerraType(), out : &A:toTerraType() )
    @out = [A:toTerraType()](@a)*[A:toTerraType()](constValue)
  end
end

function CT.tokenCounter(A,str)
  if str==nil then str="" end
  assert(type(str)=="string")
  
  local struct TokenCounter { cnt:uint, ready:bool }
  terra TokenCounter:reset() self.cnt=0 end
  terra TokenCounter:process( a : &A:toTerraType(), out : &A:toTerraType() )
    @out = @a

    if valid(a) and self.ready then
      self.cnt = self.cnt+1
      cstdio.printf(["CNT "..str..": %d\n"],self.cnt)
    end
  end

  terra TokenCounter:calculateReady(readyDownstream:bool)
  self.ready = readyDownstream
end

return MT.new(TokenCounter)
end

function CT.sum(A,B,outputType,async)
  return terra( a : &tuple(A:toTerraType(),B:toTerraType()), out : &outputType:toTerraType() )
                            @out = [outputType:toTerraType()](a._0)+[outputType:toTerraType()](a._1)
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

function CT.border(res,A,W,H,L,R,B,T,value)
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

  return MT.new(Border)
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

  return MT.new(ScaleModule)
end

function CT.broadcast(A,W,H,OT)
  return terra(inp : &A:toTerraType(), out:&OT:toTerraType() )
    for y=0,H do
      for x=0,W do (@out)[y*W+x] = @inp end
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

  return MT.new(Stencil)
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
  terra UnpackStencil:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    for i=0,[T] do
      for y=0,[stencilH] do
        for x=0,[stencilW] do
          (@out)[i][y*stencilW+x] = (@inp)[y*(stencilW+T-1)+x+i]
        end
      end
    end
  end

  return MT.new(UnpackStencil)
end

function CT.sliceTup(inputType,OT,idxLow)
  return terra( inp:&rigel.lower(inputType):toTerraType(), out:&rigel.lower(OT):toTerraType()) @out = inp.["_"..idxLow] end
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
--                         @out = @inp
                         var ot : uint8 = @inp
--                         cstdio.printf("stripmsb %d to %d\n",@inp,ot)
                         @out = ot
                       end
end

function CT.plusConsttfn(ty,value_orig)
  local value = Uniform(value_orig)
  
  local out = symbol(ty:toTerraType(true))
  local q = quote end
  if ty:verilogBits()~=ty:sizeof()*8 then
    --print(ty:verilogBits(),ty:sizeof()*8)
    --assert(false)
    q = quote @[out] = @[out] and (([ty:toTerraType()](1)<<[ty:verilogBits()])-1) end
  end

  return terra( a : ty:toTerraType(true), [out] ) 
    @[out] =  @a+[ty:toTerraType()]([value:toTerra()]) 
    [q]
  end
end

function CT.handshakeToHandshakeFramed(res,A,mixed,dims)
  local struct HandshakeToHandshakeFramed {ready:bool}
  terra HandshakeToHandshakeFramed:process( inp:&rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
    @out = @inp
  end
  terra HandshakeToHandshakeFramed:calculateReady(readyDownstream:bool) self.ready = readyDownstream end
  return MT.new(HandshakeToHandshakeFramed)
end

function CT.stripFramed(res,A)
  local struct StripFramed {ready:bool}
  terra StripFramed:process( inp:&rigel.lower(res.inputType):toTerraType(), out:&rigel.lower(res.outputType):toTerraType())
    @out = @inp
  end
  terra StripFramed:calculateReady(readyDownstream:bool) self.ready = readyDownstream end
  return MT.new(StripFramed)
end

return CT
