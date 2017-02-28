local cstdlib = terralib.includec("stdlib.h")
local rigel = require "rigel"

CT={}

function CT.identity(A)
  return terra( a : &A:toTerraType(), out : &A:toTerraType() )
                            @out = @a
                  end
end

function CT.cast(A,B)
return terra( a : &A:toTerraType(), out : &B:toTerraType() )
                            @out = [B:toTerraType()](@a)
                  end
end

function CT.tupleToArray(A,N,atup,B)
  return terra( a : &atup:toTerraType(), out : &B:toTerraType() )
                            escape
                            for i=0,N-1 do
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

function CT.sum(A,B,outputType,async)
  return terra( a : &tuple(A:toTerraType(),B:toTerraType()), out : &outputType:toTerraType() )
                            @out = [outputType:toTerraType()](a._0)+[outputType:toTerraType()](a._1)
                  end
end

function CT.argmin(ITYPE,ATYPE)
  return terra( a : &ITYPE:toTerraType(), out : &ATYPE:toTerraType() )
                            if a._0._1 <= a._1._1 then
                              @out = a._0
                            else
                              @out = a._1
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
  terra Border:reset() end
  terra Border:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    for y=0,H do for x=0,W do 
        if x<L or y<B or x>=W-R or y>=H-T then
          (@out)[y*W+x] = [value]
        else
          (@out)[y*W+x] = (@inp)[y*W+x]
        end
    end end
  end

  return Border
end

function CT.scale( res, A, w, h, scaleX, scaleY )
  local struct ScaleModule {}
  terra ScaleModule:reset() end
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

  return ScaleModule
end

function CT.broadcast(A,T,OT)
  return terra(inp : &A:toTerraType(), out:&OT:toTerraType() )
    for i=0,T do (@out)[i] = @inp end
         end
end

function CT.stencil( res, A, w, h, xmin, xmax, ymin, ymax )
  local struct Stencil {}
  terra Stencil:reset() end
  terra Stencil:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    for i=0,[w*h] do
      for y = ymin, ymax+1 do
        for x = xmin, xmax+1 do
          ((@out)[i])[(y-ymin)*(xmax-xmin+1)+(x-xmin)] = (@inp)[i+x+y*w]
        end
      end
    end
  end

  return Stencil
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
  terra UnpackStencil:reset() end
  terra UnpackStencil:process( inp : &res.inputType:toTerraType(), out : &res.outputType:toTerraType() )
    for i=0,[T] do
      for y=0,[stencilH] do
        for x=0,[stencilW] do
          (@out)[i][y*stencilW+x] = (@inp)[y*(stencilW+T-1)+x+i]
        end
      end
    end
  end

  return UnpackStencil
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

CT.plus100tfn=terra( a : &uint8, out : &uint8  ) @out =  @a+100 end

return CT