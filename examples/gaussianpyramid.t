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
                  end,1 )
-------------
touint8 = d.lift( types.int(32), types.uint(8), terra( a : &int32, out : &uint8 ) @out = [uint8](@a / 45) end, 1 )
-------------
reduceSumInt32 = d.lift( types.tuple { types.int(32), types.int(32) }, types.int(32), terra( inp : &tuple(int32,int32), out : &int32 ) @out = inp._0 + inp._1 end, 1 )
-------------
inp = d.input( types.array2d( types.uint(8), ConvWidth, ConvWidth ) )
r = d.constant( "convkernel", range(ConvArea), types.array2d( types.uint(8), ConvWidth, ConvWidth) )

packed = d.apply( "packedtup", d.packTupleArrays(7,7,{types.uint(8),types.uint(8)}), d.tuple("ptup", {inp,r}) )
conv = d.apply( "partial", d.map( partial, ConvWidth, ConvWidth ), packed)
conv = d.apply( "sum", d.reduce( reduceSumInt32, ConvWidth, ConvWidth ), conv )
conv = d.apply( "touint8", touint8, conv )

convolve = d.lambda( "convolve", inp, conv )

function downsample(W,H)
  inp = d.input( types.array2d( types.uint(8), W,H ) )
  
  local convstencils = d.apply( "convtencils", d.stencil( types.uint(8), W, H, -ConvRadius, ConvRadius, -ConvRadius, ConvRadius ), inp)
  local convpipe = d.apply( "conv", d.map( convolve, W, H ), convstencils )
  convpipe = d.apply( "convdown", d.scale( types.uint(8),W,H,1/2,1/2), convpipe )
  
  local downsample = d.lambda( "dowsamp", inp, convpipe )
  return downsample
end
-------------
inp = d.input( types.array2d( types.uint(8), W, H ) )

local totalW = W
local outs = {inp}
for l=2,Levels do
  totalW = totalW + W/math.pow(2,l-2)
  outs[l] = d.apply("blur"..l, downsample(W/math.pow(2,l-2),H/math.pow(2,l-2)), outs[l-1])
end

-------------
fin = d.apply("pyrpack", d.packPyramid(types.uint(8),W,H,Levels,true), d.tuple("pyr",outs))
fin = d.lambda( "fin", inp, fin )
module = fin:compile()

doit = d.scanlHarness( Module, W*H, "frame_128.bmp", ITYPE,W,H, "out/gaussianpyramid.bmp", ITYPE, totalW, H)
doit()