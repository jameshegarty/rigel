local d = require "darkroom"
local Image = require "image"
local types = require("types")

W = 128
H = 64
T = 4 -- throughput
ConvRadius = 3
ConvWidth = ConvRadius*2+1
ConvArea = math.pow(ConvWidth,2)

-------------
partial = d.lift( types.tuple {types.uint(8),types.uint(8)}, types.int(32), 
                  terra( a : &tuple(uint8,uint8), out : &int32 )
                    @out = [int32](a._0)*[int32](a._1)
                  end, 1 )
-------------
touint8 = d.lift( types.int(32), types.uint(8), terra( a : &int32, out : &uint8 ) @out = [uint8](@a / 45) end, 1 )
-------------
reduceSumInt32 = d.lift( types.tuple { types.int(32), types.int(32) }, types.int(32), terra( inp : &tuple(int32,int32), out : &int32 ) @out = inp._0 + inp._1 end, 1 )
-------------
inp = d.input( d.Handshake( types.array2d( types.uint(8), ConvWidth, ConvWidth ) ) )
r = d.constant( "convkernel", range(ConvArea), types.array2d( types.uint(8), ConvWidth, ConvWidth) )

conv = d.apply( "partial", d.map( partial ), d.tuple("tpart", {inp,r}) )
conv = d.apply( "sum", d.reduce( reduceSumInt32 ), conv )
conv = d.apply( "touint8", touint8, conv )

convolve = d.lambda( inp, conv )
-------------
inp = d.input( darkroom.StatefulHandshake(types.array2d( types.uint(8), T )) )

convLB = d.apply( "convLB", d.linebuffer( T, W,H, -ConvWidth+1, 0, 0, -ConvWidth+1 ), inp)
convstencils = d.apply( "convstencils", d.threadState( d.unpackStencil(ConvWidth,ConvWidth,T) ), convLB )
convpipe = d.apply( "conv", d.threadState( d.map( convolve ) ), convstencils )

convpipe = d.lambda( inp, convpipe )
-------------

convolve = convpipe:compile()

terra doit()
  var imIn : Image
  imIn:load("frame_128.bmp")
  var imOut : Image
  imOut:load("frame_128.bmp")

  for i=0,(W*H/P) do
    convolve( &([&uint8[P]](imIn.data)[i]), &([&uint8[P]](&imOut.data)[i]) )
  end

  imOut:save("conv.bmp")
end

doit()