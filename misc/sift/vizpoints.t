INFILE = arg[1]
W = tonumber(arg[2])
H = tonumber(arg[3])
outputfile = arg[4]
VIZFEATURES = (arg[5]~=nil)

print("USAGE: INFILE W H OUTFILE vizfeatures")
print("this will load in the sift features in the file and display them")
print("vizfeatures: if '1', this will write out the feature patch as a 16x8 px square")
print("   starting with the x,y coord at the top left. Features will overlap a lot!!")
      

SC = require "misc.sift.sift_common"

terra main()

  var f0 : &SC.C.FILE
  var f0_len : uint32
  f0 = SC.C.openImage( INFILE, &f0_len )
  var f0_data : &float = [&float](SC.C.malloc(f0_len))
  SC.C.loadImage( f0, f0_data, f0_len )

  if f0_len%(SC.DESC_SIZE*4)~=0 then
    SC.C.printf("Strange INFILE file length (%d)\n",f0_len)
  end

  -- thrown out trailing (garbage?) data?
  var searchCnt = (f0_len-(f0_len%(SC.DESC_SIZE*4)))/(SC.DESC_SIZE*4)

  var out = [&uint8](SC.C.malloc(W*H))

  for y=0,H do
    for x=0,W do
      out[y*W+x] = 0
    end
  end

  var featureMin:float = 10000000.f
  var featureMax:float = 0.f

  for S=0,searchCnt do
    for i=0,128 do
      var v = f0_data[S*SC.DESC_SIZE+2+i]
      if v>featureMax then featureMax=v end
      if v<featureMin then featureMin=v end
    end
  end

  SC.C.printf("FEATURE MAX: %f MIN: %f\n", featureMax, featureMin )
  
  for S=0,searchCnt do
    var x = [int](f0_data[S*SC.DESC_SIZE])
    var y = [int](f0_data[S*SC.DESC_SIZE+1])


    if VIZFEATURES then
      for j=0,8 do
        for i=0,16 do
          if y+j<H and x+i<W then
            var v = (f0_data[S*SC.DESC_SIZE+2+(j*16)+i]-featureMin)/(featureMax-featureMin)
            var ix = (y+j)*W+(x+i)
            if ix>=0 and ix<W*H then out[ix] = (v*255.f) end
          end
        end
      end
    end

    var idx = y*W+x
    if idx>=0 and idx<W*H then out[idx] = 255 end
        
  end

  SC.C.saveImage(outputfile,out,W*H)
end

main()
