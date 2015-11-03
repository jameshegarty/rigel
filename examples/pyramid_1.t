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

local TARGET_DEPTH = string.sub(arg[0],string.find(arg[0],"%d+"))
TARGET_DEPTH = tonumber(TARGET_DEPTH)


local function FIFO(fifos,statements,A,inp)
  local id = #fifos
  table.insert( fifos, d.instantiateRegistered("fifo"..tostring(id),d.fifo(A,1024)) )
  table.insert( statements, d.applyMethod("s"..tostring(id),fifos[#fifos],"store",inp) )
  return d.applyMethod("l"..tostring(id),fifos[#fifos],"load")
end

function gaussian(W,sigma)
  local center = W/2
  local tab = {}
  local sum = 0
  for y=0,W-1 do
    for x=0,W-1 do
      local a = 1/(sigma*math.sqrt(2*math.pi))
      local dist = math.sqrt(math.pow(x-center,2)+math.pow(y-center,2))
      local v = a*math.exp(-(dist*dist)/(2*sigma*sigma))
      sum = sum + v
      print(x,y,v)
      table.insert(tab,v)
    end
  end

  print("sum",sum)
  local newsum = 0
  for i=1,#tab do 
    tab[i] = math.floor((tab[i]*64/sum)+0.4)
    newsum = newsum + tab[i]
  end

  print("newsum",newsum)
  tab[4*W+4] = tab[4*W+4] + (64-newsum)

  for i=1,#tab do print(tab[i]) end

  return tab
end

local G = gaussian(8,3)
--local convolvefn = C.convolveConstant( types.uint(8), ConvWidth, rep(1,ConvWidth*ConvWidth), 6 )
local convolvefn = C.convolveConstant( types.uint(8), ConvWidth, G, 6 )

function pyramidIter(i,doDownsample,internalT,W,H)
  local inp = d.input( d.Handshake(types.array2d(A,internalT)) )
  local borderValue = 0

  local PadWidth = ConvWidth/2
  if PadWidth < internalT then PadWidth = internalT end
  local PadExtra = PadWidth-(ConvWidth/2)
  print("pyramidIter",i,"internalT",internalT,"padWIdth",PadWidth,"padextra",PadExtra)

  local internalW = W+PadWidth*2
  local internalH = H+ConvWidth
  local PS = d.padSeq(A, W, H, internalT, PadWidth, PadWidth, 4, 4, borderValue)
  print("PS",PS.sdfInput[1][1],PS.sdfInput[1][2],PS.sdfOutput[1][1],PS.sdfOutput[1][2])
  local out = d.apply("pad", d.liftHandshake(PS), inp)

  local out = d.apply( "convLB", d.makeHandshake(d.stencilLinebuffer( A, internalW, internalH, internalT, -ConvWidth+1, 0, -ConvWidth+1, 0 )), out)
  local out = d.apply( "convstencils", d.makeHandshake(d.unpackStencil( A, ConvWidth, ConvWidth, internalT )), out )
  local st_type = types.array2d(A,ConvWidth,ConvWidth)
  local CHS = d.cropHelperSeq(st_type,internalW,internalH,internalT,8+PadExtra,PadExtra,8,0)
  print("CHS",CHS.sdfInput[1][1],CHS.sdfInput[1][2],CHS.sdfOutput[1][1],CHS.sdfOutput[1][2])
  local out = d.apply( "cs", d.liftHandshake(d.liftDecimate(CHS)), out)

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
local L = {}
local SDF = {}

local outputW = 0
local outputH = inputH/math.pow(2,TARGET_DEPTH-1)

local fifos = {}
local statements = {}

local RW_TYPE = types.array2d( types.uint(8), T ) -- simulate axi bus

for depth=1,TARGET_DEPTH do
  print("DODEPTH",depth)
  local PI = pyramidIter(depth,depth>1,curT,curW,curH)
  print("PI",PI.inputType,PI.outputType)
  print(PI.sdfInput[1][1],PI.sdfInput[1][2])
  print(PI.sdfOutput[1][1],PI.sdfOutput[1][2])
  out = d.apply("p"..depth, PI, out)

  local thisW = inputW*inputH/math.pow(4,depth-1)
  print("thisW",thisW,thisW/outputH)
  outputW = outputW + thisW/outputH

  if depth>1 then
    curT = math.max(1,curT/2)
    curW = curW/2
    curH=curH/2
  end

  local THIS_TYPE = types.array2d(types.uint(8),curT)
  if depth==TARGET_DEPTH then
    -- last level
    out = FIFO(fifos,statements,THIS_TYPE, out)

    if curT~=8 then
      out = d.apply("CR"..depth,d.liftHandshake(d.changeRate(A,1,curT,8)), out)
    end
    L[depth] = out

  else
    print("curT",curT)
    out= d.apply("out_broadcast"..depth, d.broadcastStream(THIS_TYPE,2), out)
    out0 = FIFO(fifos,statements,THIS_TYPE,d.selectStream("i0"..depth,out,0))
    out1 = FIFO(fifos,statements,THIS_TYPE,d.selectStream("i1"..depth,out,1))

    if curT<8 then
      out1 = d.apply("CR"..depth,d.liftHandshake(d.changeRate(A,1,curT,8)), out1)
    end
    L[depth] = out1

    out = out0
  end


  SDF[depth] = {1,math.pow(4,depth-1)}
--  SDF[depth] = {PI.sdfOutput[1][1],PI.sdfOutput[1][2]}
--  if depth>1 then SDF[depth][1] = SDF[depth][1]/2 end
end

print("outputW",outputW,"outputH",outputH)

for k,v in ipairs(SDF) do print("SDF",v[1],v[2]) end
SDF = d.sdfNormalize(SDF)
for k,v in ipairs(SDF) do print("SDF",v[1],v[2]) end

print("TARGET_DEPTH",TARGET_DEPTH)
if TARGET_DEPTH>1 then
  SER = darkroom.serialize( RW_TYPE, SDF, d.pyramidSchedule( TARGET_DEPTH, inputW, T ) ) 
  out = darkroom.apply("toHandshakeArray", d.toHandshakeArray( RW_TYPE, SDF), d.array2d( "sa", L, TARGET_DEPTH, 1, false))
  out = darkroom.apply("ser", SER, out )
--local out = darkroom.apply("demux", darkroom.demux(RW_TYPE, d.sdfNormalize(SDF)), out )
  out = d.apply("flatten", d.flattenStreams(RW_TYPE, SDF), out )
end

table.insert(statements,1,out)

hsfn = darkroom.lambda("pyramid", inp, d.statements(statements), fifos )

local scale = math.pow(2,TARGET_DEPTH-1)



harness.axi( "pyramid_"..tostring(TARGET_DEPTH), hsfn, "frame_128.raw", nil, nil, RW_TYPE, T, inputW, inputH, RW_TYPE, T,outputW, outputH )
