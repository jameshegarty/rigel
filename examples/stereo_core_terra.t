local stereoCoreTerra={}

function stereoCoreTerra.displayOutput(ITYPE,TRESH)
return terra(a:&ITYPE:toTerraType(), out:&uint8[1])
                  @out = array(a._0)
                  if TRESH~=0 and a._1>TRESH then @out = array([uint8](0)) end
                end
end

return stereoCoreTerra