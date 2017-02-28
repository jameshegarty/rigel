local stereoTRCoreTerra = {}

function stereoTRCoreTerra.displayOutput(ITYPE,threshold)
  return terra(a:&ITYPE:toTerraType(), out:&uint8[1])
                  @out = array(a._0)
                  if threshold>0 and a._1>threshold then @out = array([uint8](0)) 
                  elseif threshold<0 and a._1<-threshold then  @out = array([uint8](0)) end
                end
end

function stereoTRCoreTerra.displayOutputColor(ITYPE,threshold)
return terra(a:&ITYPE:toTerraType(), out:&uint8[4][1])
                  var r : uint8 = (a._0-60) << 4
                  var g : uint8 = 128
--                  g = a._1 / 16
                  var b : uint8 = (16-(a._0-60)) << 4
                  @out = array(array(r,g,b,[uint8](0)))
                  if threshold>0 and a._1>threshold then @out = array(array([uint8](0),[uint8](0),[uint8](0),[uint8](0))) 
                  elseif threshold<0 and a._1<-threshold then  @out = array(array([uint8](0),[uint8](0),[uint8](0),[uint8](0))) end
                end
end

return stereoTRCoreTerra