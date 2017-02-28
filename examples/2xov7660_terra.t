return function(SPLIT_TYPE,OTYPE)
  return terra( a : &SPLIT_TYPE:toTerraType(), out : &OTYPE:toTerraType()  ) 
                  if a._0._0<320 then
                    (@out)[0] = (a._1)[0]
                    (@out)[1] = (a._1)[0]
                    (@out)[2] = (a._1)[0]
                    (@out)[3] = 0
                  else
                    (@out)[0] = (a._1)[1]
                    (@out)[1] = (a._1)[1]
                    (@out)[2] = (a._1)[1]
                    (@out)[3] = 0
                  end
                end
end