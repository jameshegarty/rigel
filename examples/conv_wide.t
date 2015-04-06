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
touint8 = d.lift( types.int(32), types.uint(8), terra( a : &int32, out : &uint8 ) @out = [uint8](@a / [(ConvWidth*ConvWidth*(ConvWidth*ConvWidth+1))/2]) end, 1 )
-------------
reduceSumInt32 = d.lift( types.tuple { types.int(32), types.int(32) }, types.int(32), terra( inp : &tuple(int32,int32), out : &int32 ) @out = inp._0 + inp._1 end, 1 )
-------------
inp = d.input( types.array2d( types.uint(8), ConvWidth, ConvWidth ) )
r = d.constant( "convkernel", range(ConvArea), types.array2d( types.uint(8), ConvWidth, ConvWidth) )

conv = d.apply( "partial", d.map( partial ), d.tuple("tpart", {inp,r}) )
conv = d.apply( "sum", d.reduce( reduceSumInt32 ), conv )
conv = d.apply( "touint8", touint8, conv )

convolve = d.lambda( "convolve", inp, conv )
-------------
ITYPE = d.Stateful(types.array2d( types.uint(8), T ))
inp = d.input( ITYPE )

convLB = d.apply( "convLB", d.linebuffer( T, W,H, -ConvWidth+1, 0, 0, -ConvWidth+1 ), inp)
convstencils = d.apply( "convstencils", d.statePassthrough( d.unpackStencil(ConvWidth,ConvWidth,T) ), convLB )
convpipe = d.apply( "conv", d.statePassthrough( d.map( convolve ) ), convstencils )

convpipe = d.lambda( "convpipe", inp, convpipe )
-------------

convolve, SimState, State = convpipe:compile()
doit = darkroom.scanlHarness( convolve, SimState, State, T, "frame_128.bmp", ITYPE, W, H, "out/conv_wide.bmp", ITYPE, W, H)
doit()
