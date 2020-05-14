SEARCH_FEATURES = arg[1]
W = tonumber(arg[2])
H = tonumber(arg[3])
TARGET_FEATURES = arg[4]
TARGET_W = tonumber(arg[5])
TARGET_H = tonumber(arg[6])
outputfile = arg[7]
THRESH = tonumber(arg[8])

print("USAGE: rigelTerra INFILE_features INFILE_W INFILE_H TARGET_features TARGET_W TARGET_H output THRESH")
print("INFILE_features is the file we are searching in")
print("TARGET_featuers is the thing we're searching for (aka the template. typically, the smaller image!)")
print("THRESH: ratio test, only return matches where the second best is less than this pct of the best (should be <=1) ",THRESH)

--print("ARG",arg[0])

local SC = require("misc.sift.sift_common")

terra match()
  var f0 : &SC.C.FILE
  var f0_len : uint32
  f0 = SC.C.openImage( SEARCH_FEATURES, &f0_len )
  var f0_data : &float = [&float](SC.C.malloc(f0_len))
  SC.C.loadImage( f0, f0_data, f0_len )

  if f0_len%(SC.DESC_SIZE*4)~=0 then
    SC.C.printf("Strange INFILE file length (%d)\n",f0_len)
  end

  var searchCnt = (f0_len-(f0_len%(SC.DESC_SIZE*4)))/(SC.DESC_SIZE*4)

  var f1 : &SC.C.FILE
  var f1_len : uint32
  f1 = SC.C.openImage( TARGET_FEATURES, &f1_len )
  var f1_data : &float = [&float](SC.C.malloc(f1_len))
  SC.C.loadImage( f1, f1_data, f1_len )

  if f1_len%(SC.DESC_SIZE*4)~=0 then
    SC.C.printf("Strange target file length\n")
    --C.exit(1)
  end

  var targetCnt = (f1_len-(f1_len%(SC.DESC_SIZE*4)))/(SC.DESC_SIZE*4)

  SC.C.printf("SearchCount %d TargetCount %d\n",searchCnt, targetCnt)

  var bestMatch : &int = [&int](SC.C.malloc(targetCnt*sizeof(int)))
  var bestMatchDist : &float = [&float](SC.C.malloc(targetCnt*sizeof(float)))
  var secondBestMatchDist : &float = [&float](SC.C.malloc(targetCnt*sizeof(float)))
  
  var max : float = 0
  var min : float = 10000000.f
  for T=0,targetCnt do
    var set : bool = false
        
    for S=0,searchCnt do
      var A = &f0_data[S*SC.DESC_SIZE+2]
      var B = &f1_data[T*SC.DESC_SIZE+2]
      var d = SC.DOT(A,B)

      -- SC.C.printf("MAG %f %f\n",SC.MAG(A), SC.MAG(B) )
      
      if (set==false or d>bestMatchDist[T]) then
        bestMatch[T] = S
        secondBestMatchDist[T] = bestMatchDist[T]
        bestMatchDist[T] = d
        set=true
      end
    end

    if bestMatchDist[T]>max then max=bestMatchDist[T] end
    if bestMatchDist[T]<min then min=bestMatchDist[T] end
  end

  SC.C.printf("MAX %f MIN %f\n",max,min)

  var out = [&uint8](SC.C.malloc(W*H*3))

  for y=0,H do
    for x=0,W do
      for c=0,3 do
        out[y*W*3+x*3+c] = 0
      end
    end
  end

  for T=0,targetCnt do
    var S = bestMatch[T]
    var x = [int](f0_data[S*SC.DESC_SIZE])
    var y = [int](f0_data[S*SC.DESC_SIZE+1])

    var targetX = [int](f1_data[T*SC.DESC_SIZE])
    var targetY = [int](f1_data[T*SC.DESC_SIZE+1])
    
    var targetXPct = ([float](targetX)/[float](TARGET_W))*[float](255)
    var targetYPct = ([float](targetY)/[float](TARGET_H))*[float](255)

    var ratio = secondBestMatchDist[T]/bestMatchDist[T]

    if ratio<THRESH then
      out[y*W*3+x*3] = [uint8](targetXPct)
      out[y*W*3+x*3+1] = [uint8](targetYPct)

      var d = (bestMatchDist[T]-min)/(max-min)
      d = d * 255
      out[y*W*3+x*3+2] = d
    end
  end

  SC.C.saveImage(outputfile,out,W*H*3)
end

match()
