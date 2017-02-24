local cstdlib = terralib.includec("stdlib.h")

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

return CT