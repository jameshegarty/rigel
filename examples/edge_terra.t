local edgeTerra={}


terra edgeTerra.nms(a:&uint8[9],out:&uint8)
                      var N = (@a)[1+1*3] >= (@a)[1+0*3]
                      var So = (@a)[1+1*3] >= (@a)[1+2*3]
                      var E = (@a)[1+1*3] >= (@a)[2+1*3]
                      var W = (@a)[1+1*3] >= (@a)[0+1*3]
                      var nmsout = (N and So) or (E and W)
                      nmsout = nmsout and ( (@a)[1+1*3] > 10 )

--                      nmsout = (@a)[1+1*3] > 10
                      if nmsout then @out=255 else @out = 0 end
end

terra edgeTerra.thresh(a:&tuple(uint8,uint32),out:&uint8[4])
                         if (@a)._0 > (@a)._1 then 
                           (@out)[0]=255 
                           (@out)[1]=255 
                           (@out)[2]=255 
                           (@out)[3]=0
                         else 
                           (@out)[0] = 0 
                           (@out)[1] = 0 
                           (@out)[2] = 0 
                           (@out)[3] = 0 
                         end
end

return edgeTerra