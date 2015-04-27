local d = require "darkroom"
local Image = require "image"
local types = require("types")

W = 128
H = 64
--ConvRadius = 3
ConvWidth = 4
ConvArea = math.pow(ConvWidth,2)
T = 1/ConvWidth

-------------
partial = d.lift( types.tuple {types.uint(8),types.uint(8)}, types.int(32), 
                  terra( a : &tuple(uint8,uint8), out : &int32 )
                    @out = [int32](a._0)*[int32](a._1)
                  end, 1 )
-------------
touint8 = d.lift( types.int(32), types.array2d(types.uint(8),1), terra( a : &int32, out : &uint8[1] ) (@out)[1] = [uint8](@a / 45) end, 1 )
-------------
reduceSumInt32 = d.lift( types.tuple { types.int(32), types.int(32) }, types.int(32), terra( inp : &tuple(int32,int32), out : &int32 ) @out = inp._0 + inp._1 end, 1 )
-------------
inp = d.input( darkroom.Stateful(types.array2d( types.uint(8), ConvWidth*T, ConvWidth )) )
r = d.apply( "convKernel", d.constSeq( split(range(ConvArea),ConvWidth), types.uint(8), ConvWidth, ConvWidth, T ), d.extractState("inext", inp) )

conv = d.apply( "partial", d.makeStateful(d.map( partial, ConvWidth*T, ConvWidth )), d.tuple("tpart", {inp,r}) )
conv = d.apply( "sum", d.makeStateful( d.reduce( reduceSumInt32, ConvWidth*T, ConvWidth )), conv )

convseq = d.lambda( "convseq", inp, conv )
-------------
inp = d.input( darkroom.StatefulRV(types.array2d( types.uint(8), ConvWidth*T, ConvWidth )) )
conv = d.apply( "convseqapply", d.RVPassthrough(convseq), inp)
conv = d.apply( "sumseq", d.RPassthrough(d.liftDecimate(d.reduceSeq( reduceSumInt32, T ))), conv )
conv = d.apply( "touint8", d.RVPassthrough(d.makeStateful(touint8)), conv )

convolve = d.lambda( "convolve", inp, conv )
-------------
ITYPE = types.array2d(types.uint(8),1)
inp = d.input( darkroom.StatefulV(ITYPE) )

convstencils = d.apply( "convtencils", d.stencilLinebufferPartial( types.uint(8), W, H, T, -ConvWidth+1, 0, -ConvWidth+1, 0), inp) -- RV
convpipe = d.apply( "conv", convolve, convstencils )

convpipe = d.lambda( "convpipe", inp, convpipe )
-------------
ITYPE = darkroom.StatefulHandshake(ITYPE)
convpipeHS = d.liftHandshake(convpipe)
Module = convpipeHS:compile()
doit = d.scanlHarnessHandshake( Module, T, "frame_128.bmp", ITYPE,W,H, "out/conv_mux.bmp", ITYPE, W, H)
doit()