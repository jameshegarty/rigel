local d = require "darkroom"
local Image = require "image"
local types = require("types")

W = 128
H = 64
ConvRadius = 3
ConvWidth = ConvRadius*2+1
ConvArea = math.pow(ConvWidth,2)
T = 4

-------------
partial = d.lift( types.tuple {types.uint(8),types.uint(8)}, types.int(32), 
                  terra( a : &tuple(uint8,uint8), out : &int32 )
                    @out = [int32](a._0)*[int32](a._1)
                  end,1 )
-------------
touint8 = d.lift( types.int(32), types.uint(8), terra( a : &int32, out : &uint8 ) @out = [uint8](@a / 1200) end, 1 )
-------------
reduceSumInt32 = d.lift( types.tuple { types.int(32), types.int(32) }, types.int(32), terra( inp : &tuple(int32,int32), out : &int32 ) @out = inp._0 + inp._1 end, 1 )
-------------
cinp = d.input( types.array2d( types.uint(8), ConvWidth, ConvWidth ) )
r = d.constant( "convkernel", range(ConvArea), types.array2d( types.uint(8), ConvWidth, ConvWidth) )

packed = d.apply( "packedtup", d.packTupleArrays(ConvWidth,ConvWidth,{types.uint(8),types.uint(8)}), d.tuple("ptup", {cinp,r}) )
conv = d.apply( "partial", d.map( partial, ConvWidth, ConvWidth ), packed)
conv = d.apply( "sum", d.reduce( reduceSumInt32, ConvWidth, ConvWidth ), conv )
conv = d.apply( "touint8", touint8, conv )

convolve = d.lambda( "convolve", cinp, conv )

function downsample(W,H)
  local dinp = d.input( d.Stateful(types.array2d( types.uint(8), T )) )
  
  local convLB = d.apply( "convLB", d.stencilLinebuffer( types.uint(8), W,H, T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), dinp)
  local convstencils = d.apply( "convstencils", d.makeStateful( d.unpackStencil( types.uint(8), ConvWidth, ConvWidth, T ) ), convLB )
  local convpipe = d.apply( "conv", d.makeStateful( d.map( convolve, T ) ), convstencils )
  convpipe = d.apply( "convdown", d.downsampleSeq( types.uint(8), W, H, T, 1/2, 1/2 ), convpipe )
  
  local downsample = d.lambda( "dowsamp", dinp, convpipe )
  return d.liftHandshake(d.liftDecimate(downsample))
--  return d.makeHandshake(downsample)
end
-------------
ITYPE = d.StatefulHandshake(types.array2d( types.uint(8), T ))
inp = d.input( ITYPE )

local out = d.apply("blur", downsample(W,H), inp)

-------------
fin = d.lambda( "fin", inp, out )
Module = fin:compile()

doit = d.scanlHarnessHandshake( Module, T, "frame_128.bmp", ITYPE,W,H, T, "out/downsample_wide.bmp", fin.outputType, W/2, H/2,0,0,0,0)
doit()