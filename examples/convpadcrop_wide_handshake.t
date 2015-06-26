local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")

T = 8 -- throughput
--ConvRadius = 1
ConvRadius = 2
ConvWidth = ConvRadius*2+1
ConvArea = math.pow( ConvWidth, 2 )

inputW = 128
inputH = 64

PadRadius = upToNearest(T, ConvRadius)

-- expand to include crop region
--W = upToNearest(T,128+ConvWidth-1)
--H = 64+ConvWidth-1

internalW = inputW+PadRadius*2
internalH = inputH+ConvRadius*2

--outputW = internalW
--outputH = internalH

outputW = inputW
outputH = inputH

-------------
sinp = S.parameter( "inp", types.tuple {types.uint(8),types.uint(8)} )
partial = d.lift( "partial", types.tuple {types.uint(8),types.uint(8)}, types.int(32), 1,
                  terra( a : &tuple(uint8,uint8), out : &int32 )
                    @out = [int32](a._0)*[int32](a._1)
                  end, sinp, S.cast(S.index(sinp,0),types.int(32))*S.cast(S.index(sinp,1),types.int(32)) )
-------------
touint8inp = S.parameter("inp", types.int(32))
touint8 = d.lift( "touint8", types.int(32), types.uint(8), 1, terra( a : &int32, out : &uint8 ) @out = [uint8](@a >> 5) end, touint8inp, S.cast(S.rshift(touint8inp,S.constant(5,types.int(32))), types.uint(8)) )
-------------
rsinp = S.parameter( "inp", types.tuple { types.int(32), types.int(32) } )
reduceSumInt32 = d.lift( "reduceSumInt32", types.tuple { types.int(32), types.int(32) }, types.int(32), 1, terra( inp : &tuple(int32,int32), out : &int32 ) @out = inp._0 + inp._1 end, rsinp, S.index(rsinp,0)+S.index(rsinp,1) )
-------------
inp = d.input( types.array2d( types.uint(8), ConvWidth, ConvWidth ) )
kernel = rep(1,ConvWidth*ConvWidth)
r = d.constant( "convkernel", kernel, types.array2d( types.uint(8), ConvWidth, ConvWidth) )

packed = d.apply( "packedtup", d.SoAtoAoS(ConvWidth,ConvWidth,{types.uint(8),types.uint(8)}), d.tuple("ptup", {inp,r}) )
conv = d.apply( "partial", d.map( partial, ConvWidth, ConvWidth ), packed )
conv = d.apply( "sum", d.reduce( reduceSumInt32, ConvWidth, ConvWidth ), conv )
conv = d.apply( "touint8", touint8, conv )

convolve = d.lambda( "convolve", inp, conv )
-------------
BASE_TYPE = types.array2d( types.uint(8), T )
ITYPE = d.Stateful(BASE_TYPE)
inp = d.input( ITYPE )

--I = d.apply("crop", d.cropSeq(types.uint(8),W,H,T,ConvWidth,0,ConvWidth,0,0), inp)
convLB = d.apply( "convLB", d.stencilLinebuffer( types.uint(8), internalW, internalH, T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), inp)
convstencils = d.apply( "convstencils", d.makeStateful( d.unpackStencil( types.uint(8), ConvWidth, ConvWidth, T ) ), convLB )
convpipe = d.apply( "conv", d.makeStateful( d.map( convolve, T ) ), convstencils )

convpipe = d.lambda( "convpipe", inp, convpipe )
-------------
hsfn = d.makeHandshake(convpipe)
----------------
inp = d.input( d.StatefulHandshake(types.null()) )
out = d.apply("fread",d.makeHandshake(d.freadSeq("frame_128.raw",BASE_TYPE,"../frame_128.raw")),inp)
--out = d.apply("pad", d.liftHandshake(d.padSeq(types.uint(8), inputW, inputH, T, (W-inputW), 0, (H-inputH), 0, 0)), out )
out = d.apply("pad", d.liftHandshake(d.padSeq(types.uint(8), inputW, inputH, T, PadRadius, PadRadius, ConvRadius, ConvRadius, 0)), out)
out = d.apply("conv_wide", hsfn, out )
out = d.apply("crop",d.liftHandshake(d.liftDecimate(d.cropHelperSeq(types.uint(8), internalW, internalH, T, PadRadius+ConvRadius, PadRadius-ConvRadius, ConvRadius*2, 0, 0))), out)
out = d.apply("fwrite", d.makeHandshake(d.fwriteSeq("out/convpadcrop_wide_handshake.raw",BASE_TYPE,"convpadcrop_wide_handshake.sim.raw")), out )
harness = d.lambda( "harness", inp, out )
-------------
f = d.seqMapHandshake( harness, inputW, inputH, outputW, outputH, T,false )
Module = f:compile()
(terra() var m:Module; m:reset(); m:process(nil,nil) end)()

io.output("out/convpadcrop_wide_handshake.sim.v")
io.write(f:toVerilog())
io.close()
----------
fnaxi = d.seqMapHandshake( hsfn, inputW, inputH, outputW, outputH, T, true )
io.output("out/convpadcrop_wide_handshake.axi.v")
io.write(fnaxi:toVerilog())
io.close()
--------
d.writeMetadata("out/convpadcrop_wide_handshake.metadata.lua", outputW, outputH,1,1,"frame_128.raw")


--Module = convpipe:compile()
--doit = darkroom.scanlHarness( Module, T, "frame_128.bmp", ITYPE, W, H, T, "out/conv_wide.bmp", ITYPE, W, H,ConvWidth,0,ConvWidth,0)
--doit()
