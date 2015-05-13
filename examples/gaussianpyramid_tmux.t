local d = require "darkroom"
local Image = require "image"
local types = require("types")

W = 128
H = 64
--ConvRadius = 3
ConvWidth = 4
ConvArea = math.pow(ConvWidth,2)
T=1

Levels = 4
-------------
partial = d.lift( types.tuple {types.uint(8),types.uint(8)}, types.int(32), 
                  terra( a : &tuple(uint8,uint8), out : &int32 )
                    @out = [int32](a._0)*[int32](a._1)
                  end,1 )
-------------
touint8 = d.lift( types.int(32), types.array2d(types.uint(8),1), terra( a : &int32, out : &uint8[1] ) (@out)[1] = [uint8](@a / 130) end, 1 )
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
  local convpipe = d.apply( "convdown", d.downsampleSeq( types.uint(8), W, H, T, 1/2, 1/2 ), dinp )  
  local downsample = d.lambda( "dowsamp_"..W, dinp, convpipe )
  return d.liftHandshake(d.liftDecimate(downsample))
end

function st(W,H)
  local dinp = d.input( d.Stateful(types.array2d( types.uint(8), T )) )
  local convLB = d.apply( "convLB", d.stencilLinebuffer( types.uint(8), W,H, T, -ConvWidth+1, 0, -ConvWidth+1, 0 ), dinp)
  local UP = d.unpackStencil( types.uint(8), ConvWidth, ConvWidth, T )
  local convstencils = d.apply( "convstencils", d.makeStateful( UP ), convLB )
  convstencils = d.apply( "i", d.makeStateful(d.index( UP.outputType, 0 )), convstencils)
  local downsample = d.lambda( "st_"..W, dinp, convstencils )
  return d.makeHandshake(downsample)
end

-------------
ITYPE = d.StatefulHandshake(types.array2d( types.uint(8), T ))
inp = d.input( ITYPE )

local inputList = {}
for l=1,Levels do
  table.insert( inputList, {1,l} )
end

local tmux = d.tmux( convolve, inputList )
local tmuxOutputs = d.applyRegLoad( "tmux", tmux, d.extractState("tmuxouts", inp ) )

local totalW = W
local tmuxInputs = {d.apply("ST0",st(W,H),inp)}
local outs = {inp}
local internalRouting = {'x'}
for l=2,Levels do
  totalW = totalW + W/math.pow(2,l-1)
  local ip = d.apply( "idx"..l, d.index( darkroom.stripRegistered(tmux.outputType), l-2), tmuxOutputs )
  outs[l] = d.apply("ds"..l, downsample(W/math.pow(2,l-2),H/math.pow(2,l-2)), ip )
  table.insert( tmuxInputs, d.apply("st"..l, st(W/math.pow(2,l-2),H/math.pow(2,l-2)), outs[l]) )
end

local tmuxInputs = d.applyRegStore( "tmux", tmux, d.tuple("tmxi",tmuxInputs) )

-------------
fin = d.apply("pyrpack", d.packPyramidSeq(types.uint(8),W,H,T,Levels,true), d.tuple("pyr",outs))
fin = d.catState("cats", fin, tmuxInputs)
fin = d.lambda( "fin", inp, fin )
Module = fin:compile()
print("TOTALW",totalW,fin.outputType)

doit = d.scanlHarnessHandshake( Module, T, "frame_128.bmp", ITYPE,W,H, T, "out/gaussianpyramid_wide.bmp", fin.outputType, totalW, H,0,0,0,0)
doit()