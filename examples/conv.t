local d = require "darkroom"
local Image = require "image"
local types = require("types")

ConvRadius = 1
ConvWidth = ConvRadius*2+1
ConvArea = math.pow(ConvWidth,2)
W = 128+ConvRadius*2
H = 64+ConvRadius*2

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
inp = d.input( types.array2d( types.uint(8), ConvWidth, ConvWidth ) )
r = d.constant( "convkernel", range(ConvArea), types.array2d( types.uint(8), ConvWidth, ConvWidth) )

packed = d.apply( "packedtup", d.packTupleArrays(ConvWidth,ConvWidth,{types.uint(8),types.uint(8)}), d.tuple("ptup", {inp,r}) )
conv = d.apply( "partial", d.map( partial, ConvWidth, ConvWidth ), packed )
conv = d.apply( "sum", d.reduce( reduceSumInt32, ConvWidth, ConvWidth ), conv )
conv = d.apply( "touint8", touint8, conv )

convolve = d.lambda( "convolve", inp, conv )
-------------
ITYPE = types.array2d( types.uint(8), W,H )
inp = d.input( ITYPE )

I = d.apply("crop", d.crop(types.uint(8),W,H,ConvRadius,ConvRadius,ConvRadius,ConvRadius,0), inp )
convstencils = d.apply( "convtencils", d.stencil( types.uint(8),W,H,-ConvRadius, ConvRadius, -ConvRadius, ConvRadius ), I)
convpipe = d.apply( "conv", d.map( convolve, W, H ), convstencils )

convpipe = d.lambda( "convpipe", inp, convpipe )
-------------

Module = convpipe:compile()
doit = d.scanlHarness( Module, W*H, "frame_128.bmp", ITYPE,W,H, "out/conv.bmp", ITYPE, W, H, ConvRadius,ConvRadius,ConvRadius,ConvRadius)
doit()
