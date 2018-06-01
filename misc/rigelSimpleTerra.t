local RST = {}

function RST.sumPow2(A,B,outputType)
  return terra( a : &tuple(A:toTerraType(),B:toTerraType()), out : &outputType:toTerraType() )
                            @out = [outputType:toTerraType()](a._0)+([outputType:toTerraType()](a._1)*[outputType:toTerraType()](a._1))
                  end
end

return RST