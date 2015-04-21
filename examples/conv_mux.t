local d = require "darkroom"
local Image = require "image"
local types = require("types")

W = 128
H = 64
ConvRadius = 3
ConvWidth = ConvRadius*2+1
ConvArea = math.pow(ConvWidth,2)
T = 1/ConvWidth

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
inp = d.input( darkroom.Stateful(types.array2d( types.uint(8), ConvWidth*T, ConvWidth )) )
r = d.apply( "convKernel", d.constSeq( split(range(ConvArea),ConvWidth), types.array2d( types.uint(8), ConvWidth, ConvWidth), T ), d.index("getstate",inp,1) )

conv = d.apply( "partial", d.statePassthrough(d.map( partial )), d.tuple("tpart", {inp,r}) )
conv = d.apply( "sum", d.statePassthrough(d.reduce( reduceSumInt32 )), conv )
conv = d.apply( "sumseq", d.reduceSeq( reduceSumInt32, T ), conv )

convseq = d.lambda( "convseq", inp, conv )
-------------
inp = d.input( darkroom.StatefulHandshake(types.array2d( types.uint(8), ConvWidth*T, ConvWidth )) )
conv = d.apply( "convseqapply", d.makeHandshake(convseq), inp)
conv = d.apply( "touint8", d.makeHandshake(d.statePassthrough(touint8)), conv )

convolve = d.lambda( "convolve", inp, conv )
-------------
inp = d.input( darkroom.StatefulHandshake(types.uint(8)) )

convstencils = d.apply( "convtencils", d.linebufferPartial( -ConvWidth, -ConvWidth,  T), inp)
convpipe = d.apply( "conv", convolve, convstencils )

convpipe = d.lambda( "convpipe", inp, convpipe )
-------------

convolve = convpipe:compile()

terra doit()
  var imIn : Image
  imIn:load("frame_128.bmp")
  var imOut : Image
  imOut:load("frame_128.bmp")

  convolve( [&uint8[W*H]](imIn.data), [&uint8[W*H]](imOut.data) )
  imOut:save("conv.bmp")
end

doit()