local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"

T = 8 -- throughput
A = types.uint(8)

local ConvWidth = 8

local inputW = 128
local inputH = 64

local outputW = inputW
local outputH = inputH

local convolvefn = C.convolveConstant( types.uint(8), ConvWidth, rep(1,ConvWidth*ConvWidth), 6 )

function pyramidIter(i,doDownsample,internalT,W,H)
  local inp = d.input( d.Handshake(types.array2d(A,internalT)) )
  local borderValue = 0
  local internalW = W+ConvWidth
  local internalH = H+ConvWidth
  local out = d.apply("pad", d.liftHandshake(d.padSeq(A, W, H, internalT, 4, 4, 4, 4, borderValue)), inp)

  local out = d.apply( "convLB", d.makeHandshake(d.stencilLinebuffer( A, internalW, internalH, internalT, -ConvWidth+1, 0, -ConvWidth+1, 0 )), out)
  local out = d.apply( "convstencils", d.makeHandshake(d.unpackStencil( A, ConvWidth, ConvWidth, internalT )), out )
  local st_type = types.array2d(A,ConvWidth,ConvWidth)
  local out = d.apply( "cs", d.liftHandshake(d.liftDecimate(d.cropSeq(st_type,internalW,internalH,internalT,8,0,8,0))), out)

  local scaleX, scaleY = 2,2

  local convT = internalT
  if doDownsample then
    out = darkroom.apply("downsampleSeq_Y", d.liftHandshake(darkroom.liftDecimate(darkroom.downsampleYSeq( st_type, W, H, internalT, scaleY ))), out)
    out = darkroom.apply("downsampleSeq_X", d.liftHandshake(darkroom.liftDecimate(darkroom.downsampleXSeq( st_type, W, H, internalT, scaleX ))), out)
    convT = math.max(1,internalT/2)
  end

  out = d.apply("conv", d.makeHandshake(d.map(convolvefn,convT)), out)

  return darkroom.lambda("pyramid"..i, inp, out )
end

local inp = d.input( d.Handshake(types.array2d(A,T)) )
local out = inp
curT = T
curW = inputW
curH = inputH
for depth=1,2 do
  print("DODEPTH",depth)
  out = d.apply("p"..depth, pyramidIter(depth,depth>1,curT,curW,curH), out)
  if depth>1 then
    curT = math.max(1,curT/2)
    curW = curW/2
    curH=curH/2
  end
end

out = d.apply("CR",d.liftHandshake(d.changeRate(A,1,4,8)), out)
hsfn = darkroom.lambda("pyramid", inp, out )

local scale = 2
local RW_TYPE = types.array2d( types.uint(8), T ) -- simulate axi bus
harness.axi( "resample_wide_handshake", hsfn, "frame_128.raw", nil, nil, RW_TYPE, T, inputW, inputH, RW_TYPE, T,outputW/scale, outputH/scale )
