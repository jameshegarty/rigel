local d = require "darkroom"
local Image = require "image"
local types = require("types")

W = 128
H = 64
--ConvRadius = 3
ConvWidth = 4
ConvArea = math.pow(ConvWidth,2)
if rawget(_G,"T")==nil then T = 1/ConvWidth end
W = W + ConvWidth
H = H + ConvWidth
-------------
partial = d.lift( types.tuple {types.uint(8),types.uint(8)}, types.int(32), 
                  terra( a : &tuple(uint8,uint8), out : &int32 )
                    @out = [int32](a._0)*[int32](a._1)
--                    @out = [int32](a._1)
                  end, 1 )
-------------
touint8 = d.lift( types.int(32), types.array2d(types.uint(8),1), terra( a : &int32, out : &uint8[1] ) (@out)[0] = [uint8](@a / 120) end, 1 )
-------------
reduceSumInt32 = d.lift( types.tuple { types.int(32), types.int(32) }, types.int(32), terra( inp : &tuple(int32,int32), out : &int32 ) @out = inp._0 + inp._1 end, 1 )
reduceSumInt32_0cyc = d.lift( types.tuple { types.int(32), types.int(32) }, types.int(32), terra( inp : &tuple(int32,int32), out : &int32 ) @out = inp._0 + inp._1 end, 0 )
-------------
inp = d.input( darkroom.Stateful(types.array2d( types.uint(8), ConvWidth*T, ConvWidth )) )
local V = range(ConvArea)
--for i=1,ConvArea do V[i] = 0 end
--V[3] = 255
r = d.apply( "convKernel", d.constSeq( V, types.uint(8), ConvWidth, ConvWidth, T ), d.extractState("inext", inp) )

packed = d.apply( "packedtup", d.packTupleArraysStateful(ConvWidth*T,ConvWidth,{types.uint(8),types.uint(8)}), d.tuple("ptup", {inp,r}) )
conv = d.apply( "partial", d.makeStateful(d.map( partial, ConvWidth*T, ConvWidth )), packed )
conv = d.apply( "sum", d.makeStateful( d.reduce( reduceSumInt32, ConvWidth*T, ConvWidth )), conv )

convseq = d.lambda( "convseq", inp, conv )

-------------
inp = d.input( darkroom.StatefulRV(types.array2d( types.uint(8), ConvWidth*T, ConvWidth )) )
conv = d.apply( "convseqapply", d.RVPassthrough(convseq), inp)
conv = d.apply( "sumseq", d.RPassthrough(d.liftDecimate(d.reduceSeq( reduceSumInt32_0cyc, T ))), conv )
conv = d.apply( "touint8", d.RVPassthrough(d.makeStateful(touint8)), conv )

convolve = d.lambda( "convolve", inp, conv )
-------------
ITYPE = types.array2d(types.uint(8),1)
inp = d.input( darkroom.StatefulV(ITYPE) )

I = d.apply("crop", d.liftDecimate(d.liftStateful(d.cropSeq(types.uint(8),W,H,1,ConvWidth,0,ConvWidth,0,0))), inp)
convstencils = d.apply( "convtencils", d.RPassthrough(d.stencilLinebufferPartial( types.uint(8), W, H, T, -ConvWidth+1, 0, -ConvWidth+1, 0)), I) -- RV
convpipe = d.apply( "conv", convolve, convstencils )

convpipe = d.lambda( "convpipe", inp, convpipe )
-------------
ITYPE = darkroom.StatefulHandshake(ITYPE)
convpipeHS = d.liftHandshake(convpipe)
Module = convpipeHS:compile()
doit = d.scanlHarnessHandshake( Module, T, "frame_128.bmp", ITYPE,W,H, T, "out/conv_mux_"..(1/T)..".bmp", convpipeHS.outputType, W, H, ConvWidth, 0, ConvWidth, 0)
doit()