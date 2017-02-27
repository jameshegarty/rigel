local siftTerra = {}

function siftTerra.sumPow2(A,B,outputType)
  return terra( a : &tuple(A:toTerraType(),B:toTerraType()), out : &outputType:toTerraType() )
                            @out = [outputType:toTerraType()](a._0)+([outputType:toTerraType()](a._1)*[outputType:toTerraType()](a._1))
         end
end

function siftTerra.posSub(ITYPE,x,y)
return terra( a : &ITYPE:toTerraType(), out:&ITYPE:toTerraType() )
                      var xo = a._0-x
                      var yo = a._1-y
                      @out = {xo,yo}
                    end
end

return siftTerra