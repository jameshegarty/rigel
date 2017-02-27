local campipeCoreTerra={}

function campipeCoreTerra.demosaic(DEMOSAIC_W,DEMOSAIC_H,phaseX,phaseY,tab)
return terra(inp:&tuple(uint16,uint16),out:&uint8[DEMOSAIC_W*DEMOSAIC_H])
                           var x,y = inp._0,inp._1
                           var phase = ((x+phaseX)%2)+((y+phaseY)%2)*2
                           var ot : int32[DEMOSAIC_W*DEMOSAIC_H]
                           if phase==0 then ot = array([tab[1]])
                           elseif phase==1 then ot = array([tab[2]])
                           elseif phase==2 then ot = array([tab[3]])
                           else ot = array([tab[4]]) end
                           for i=0,DEMOSAIC_W*DEMOSAIC_H do (@out)[i] = ot[i] end
                         end
end

return campipeCoreTerra