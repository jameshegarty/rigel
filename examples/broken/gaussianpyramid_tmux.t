local d = require "darkroom"
local Image = require "image"
local types = require("types")

W = 128
H = 64
ConvRadius = 3
ConvWidth = ConvRadius*2+1
ConvArea = math.pow(ConvWidth,2)
T = 1

Levels = 4
-------------
partial = d.lift( types.tuple {types.uint(8),types.uint(8)}, types.int(32), 
                  terra( a : &tuple(uint8,uint8), out : &int32 )
                    @out = [int32](a._0)*[int32](a._1)
                  end )
-------------
touint8 = d.lift( types.int(32), types.uint(8), terra( a : &int32, out : &uint8 ) @out = [uint8](@a / 45) end )
-------------
inp = d.input( types.array2d( types.uint(8), ConvWidth, ConvWidth ) )
r = d.constant( range(ConvArea), types.array2d( types.uint(8), ConvWidth, ConvWidth) )

conv = d.apply( "partial", d.map2d( partial ), d.tuple {inp,r} )
conv = d.apply( "sum", d.reduce( conv ), conv )
conv = d.apply( "touint8", touint8, conv )

convolve = d.lambda( inp, conv )
-------------
inp = d.input( types.array( types.uint(8), T ) )

convpipe = d.apply( "convdown", d.downSeq(W,H,2,2), inp )
convstencils = d.apply( "convtencils", d.linebuffer( T, W, H, -ConvWidth, -ConvWidth ), inp)

downsample = d.lambda( inp, convpipe )
-------------
inp = d.input( types.array( types.uint(8), T ) )
inp = d.apply( "inplb", d.linebuffer( T, W, H, -ConvWidth, -ConvWidth ), inp )

local inoutMap = {'x'}
local Gs = {'x'}
for l=2,Levels do
  inoutMap[i] = i-2
  Gs[i] = downsample
end

tmuxconvolve = d.tmux( convolve, inoutMap, Gs )
fin = d.apply("tmuxconvolve", tmuxconvolve, inp )
-------------

gaussianpyramid = fin:compile()

terra doit()
  var imIn : Image
  imIn:load("frame_128.bmp")
  var imOut : Image
  imOut:load("frame_128.bmp")

  convolve( [&uint8[W*H]](imIn.data), [&uint8[W*H]](imOut.data) )
  imOut:save("conv.bmp")
end

doit()