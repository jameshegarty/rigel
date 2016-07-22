local d = require "darkroom"
local Image = require "image"
local types = require("types")

T = 4 -- throughput
--ConvRadius = 1
ConvWidth = 4
ConvArea = math.pow(ConvWidth,2)

W = 128+ConvWidth
H = 64+ConvWidth

-------------
partial = d.lift( types.tuple {types.uint(8),types.uint(8)}, types.int(32), 
                  terra( a : &tuple(uint8,uint8), out : &int32 )
                    @out = [int32](a._0)*[int32](a._1)
                  end, 1 )
-------------
touint8 = d.lift( types.int(32), types.uint(8), terra( a : &int32, out : &uint8 ) @out = [uint8](@a / 120) end, 1 )
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
ITYPE = d.Stateful(types.array2d( types.uint(8), T ))
inp = d.input( ITYPE )

I = d.apply("crop", d.cropSeq(types.uint(8),W,H,T,ConvWidth,0,ConvWidth,0,0), inp)
convLB = d.apply( "convLB", d.stencilLinebuffer( types.uint(8), W,H, T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), I)
convstencils = d.apply( "convstencils", d.makeStateful( d.unpackStencil( types.uint(8), ConvWidth, ConvWidth, T ) ), convLB )
convpipe = d.apply( "conv", d.makeStateful( d.map( convolve, T ) ), convstencils )

convpipe = d.lambda( "convpipe", inp, convpipe )
-------------

Module = convpipe:compile()
doit = darkroom.scanlHarness( Module, T, "frame_128.bmp", ITYPE, W, H, T, "out/conv_wide.bmp", ITYPE, W, H,ConvWidth,0,ConvWidth,0)
doit()
