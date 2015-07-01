local d = require "darkroom"
local Image = require "image"
local types = require("types")

W = 128
H = 64
--ConvRadius = 3
ConvWidth = 16
ConvArea = math.pow(ConvWidth,2)
--T = 4

Levels = 4
-------------
partial = d.lift( types.tuple {types.uint(8),types.uint(8)}, types.int(32), 
                  terra( a : &tuple(uint8,uint8), out : &int32 )
                    @out = [int32](a._0)*[int32](a._1)
                  end,1 )
-------------
touint8 = d.lift( types.int(32), types.array2d(types.uint(8),1), terra( a : &int32, out : &uint8[1] ) (@out)[0] = [uint8](@a / 130) end, 1 )
-------------
reduceSumInt32 = d.lift( types.tuple { types.int(32), types.int(32) }, types.int(32), terra( inp : &tuple(int32,int32), out : &int32 ) @out = inp._0 + inp._1 end, 1 )
reduceSumInt32_0cyc = d.lift( types.tuple { types.int(32), types.int(32) }, types.int(32), terra( inp : &tuple(int32,int32), out : &int32 ) @out = inp._0 + inp._1 end, 0 )
-------------
function conv(cycW)
  local cinp = d.input( darkroom.Stateful(types.array2d( types.uint(8), cycW, ConvWidth )) )
--  r = d.constant( "convkernel", range(ConvArea), types.array2d( types.uint(8), ConvWidth, ConvWidth) )
  local V = range(ConvArea)
  local r = d.apply( "convKernel"..cycW, d.constSeq( V, types.uint(8), ConvWidth, ConvWidth, cycW/ConvWidth ), d.extractState("inext", cinp) )

  local packed = d.apply( "packedtup", d.packTupleArraysStateful( cycW, ConvWidth, {types.uint(8),types.uint(8)}), d.tuple("ptup", {cinp,r}) )
  local conv = d.apply( "partial", d.makeStateful(d.map( partial, cycW, ConvWidth )), packed)
  conv = d.apply( "sum", d.makeStateful(d.reduce( reduceSumInt32, cycW, ConvWidth )), conv )

  local convolve = d.lambda( "convolve", cinp, conv )
  return convolve
end

function downsample(W,H,cycW)
  local I = d.input( d.StatefulV(types.array2d( types.uint(8), 1 )) )
  
  local convstencils = d.apply( "convtencils", d.stencilLinebufferPartial( types.uint(8), W, H, cycW/ConvWidth, -ConvWidth+1, 0, -ConvWidth+1, 0), I) -- RV
  local convpipe = d.apply( "conv", d.RVPassthrough(  conv(cycW) ), convstencils )
  convpipe = d.apply( "sumseq", d.RPassthrough(d.liftDecimate(d.reduceSeq( reduceSumInt32_0cyc, cycW/ConvWidth ))), convpipe )
  convpipe = d.apply( "touint8", d.RVPassthrough(d.makeStateful(touint8)), convpipe )
  convpipe = d.apply( "convdown", d.RPassthrough(d.liftDecimate(d.downsampleSeq( types.uint(8), W, H, 1, 1/2, 1/2 ))), convpipe )
  
  local downsample = d.lambda( "dowsamp_"..W, I, convpipe )
  return d.liftHandshake(downsample)
end
-------------
ITYPE = d.StatefulHandshake(types.array2d( types.uint(8), 1 ))
inp = d.input( ITYPE )

local totalW = W
local outs = {inp}
for l=2,Levels do
  totalW = totalW + W/math.pow(2,l-1)
  local cycW = ConvWidth/math.pow(4,l-2)
  outs[l] = d.apply("blur"..l, downsample( W/math.pow(2,l-2), H/math.pow(2,l-2), cycW ), outs[l-1])
end

-------------
fin = d.apply("pyrpack", d.packPyramidSeq(types.uint(8),W,H,1,Levels,true), d.tuple("pyr",outs))
fin = d.lambda( "fin", inp, fin )
Module = fin:compile()
print("TOTALW",totalW,fin.outputType)

doit = d.scanlHarnessHandshake( Module, 1, "frame_128.bmp", ITYPE,W,H, 1, "out/gaussianpyramid_smux.bmp", fin.outputType, totalW, H,0,0,0,0)
doit()