local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"
local P = require "pyramid_core"

internalT = 4 -- internal throughput
outputT = 8
A = types.uint(8)

local LARGE = string.find(arg[0],"large")
LARGE = (LARGE~=nil)
local NOFIFO = string.find(arg[0],"nofifo")
NOFIFO = (NOFIFO~=nil)

local ConvWidth = 8

local inputW = 128
local inputH = 64

if LARGE then
  inputW, inputH = 384, 384
end

local TARGET_DEPTH = string.sub(arg[0],string.find(arg[0],"%d+"))
TARGET_DEPTH = tonumber(TARGET_DEPTH)

local TAP_TYPE = types.array2d( types.uint(8), ConvWidth, ConvWidth ):makeConst()
local DATA_TYPE = types.array2d(A,8)
local HST = types.tuple{DATA_TYPE,TAP_TYPE}

local inp = d.input( d.Handshake(HST) )
local tapinp =  d.apply("idx1",d.makeHandshake(d.index(HST,1)),inp)
local out = d.apply("idx0",d.makeHandshake(d.index(HST,0)),inp)

if internalT<8 then
  out = d.apply("CRtop",d.liftHandshake(d.changeRate(A,1,8,internalT)), out)
end

curT = internalT
curW = inputW
curH = inputH
local L = {}
local SDF = {}

local outputW = 0
local outputH = inputH/math.pow(2,TARGET_DEPTH-1)

local fifos = {}
local statements = {}


for depth=1,TARGET_DEPTH do
  print("DODEPTH",depth)
  --local PI = P.pyramidIter(depth,depth>1,internalT,curW,curH,ConvWidth)
  local PI = P.pyramidIterTaps( depth, depth>1, internalT, curW, curH, ConvWidth, NOFIFO )
  print("PI",PI.inputType,PI.outputType)
  print(PI.sdfInput[1][1],PI.sdfInput[1][2])
  print(PI.sdfOutput[1][1],PI.sdfOutput[1][2])

  local piinp = d.apply("CPI"..depth, darkroom.packTuple({types.array2d(A,internalT),TAP_TYPE}), d.tuple("CONVPIPEINP"..depth,{out,tapinp},false))
  out = d.apply("p"..depth, PI, piinp)

  local thisW = inputW*inputH/math.pow(4,depth-1)
  print("thisW",thisW,thisW/outputH)
  outputW = outputW + thisW/outputH

  if depth>1 then
    curT = internalT/4 -- we do changeRate so that this is always true for this implementation
    curW = curW/2
    curH = curH/2
  end

  local THIS_TYPE = types.array2d(types.uint(8),curT)
  local TOP_TYPE = types.array2d(A,internalT)
  local OUT_TYPE = types.array2d(A,8)
  if depth==TARGET_DEPTH then

    -- we must do the changerate _before_ the fifo, or the things later will run at 1/2 rate we expect
    out = d.apply("CR"..depth,d.liftHandshake(d.changeRate(A,1,curT,8)), out)

    -- last level
    out = P.FIFO(fifos,statements,OUT_TYPE, out,nil, "final", curW, curH, 8 )
    L[depth] = out
  else
    print("curT",curT)

    out = d.apply("out_broadcast"..depth, d.broadcastStream(THIS_TYPE,2), out)
    local out0 = d.selectStream("i0"..depth,out,0)
    if curT~=internalT then
      out0 = d.apply("CR"..depth,d.liftHandshake(d.changeRate(A,1,curT,internalT)), out0 )
    end
    out0 = P.FIFO( fifos, statements, TOP_TYPE, out0, nil, "internal"..depth, curW, curH, internalT )

    local out1 = d.apply("CRr"..depth,d.liftHandshake(d.changeRate(A,1,curT,8)), d.selectStream("i1"..depth,out,1) )
    out1 = P.FIFO( fifos, statements, OUT_TYPE, out1, nil, "output"..depth, curW, curH, 8 )

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

local RW_TYPE = types.array2d( types.uint(8), 8 ) -- simulate axi bus

print("TARGET_DEPTH",TARGET_DEPTH)
if TARGET_DEPTH>1 then
  SER = darkroom.serialize( RW_TYPE, SDF, d.pyramidSchedule( TARGET_DEPTH, inputW, outputT ) ) 
  out = darkroom.apply("toHandshakeArray", d.toHandshakeArray( RW_TYPE, SDF), d.array2d( "sa", L, TARGET_DEPTH, 1, false))
  out = darkroom.apply("ser", SER, out )
--local out = darkroom.apply("demux", darkroom.demux(RW_TYPE, d.sdfNormalize(SDF)), out )
  out = d.apply("flatten", d.flattenStreams(RW_TYPE, SDF), out )
end

if outputT~=8 then
  out = d.apply("CRend",d.liftHandshake(d.changeRate(A,1,outputT,8)), out)
end

table.insert(statements,1,out)

hsfn = darkroom.lambda("pyramid", inp, d.statements(statements), fifos )

local scale = math.pow(2,TARGET_DEPTH-1)

local infile = "frame_128.raw"
local outfile = "pyramid_taps_"..tostring(TARGET_DEPTH)
local design = "Gaussian Pyramid 128"

if LARGE then
  infile = "frame_384_384.raw"
  if NOFIFO then
    outfile = "pyramid_large_nofifo_taps_"..tostring(TARGET_DEPTH)
    design = "Gaussian Pyramid NOFIFO 384"
  else
    outfile = "pyramid_large_taps_"..tostring(TARGET_DEPTH)
    design = "Gaussian Pyramid 384"
  end
end

harness.axi( outfile, hsfn, infile, TAP_TYPE, P.G, RW_TYPE, 8, inputW, inputH, RW_TYPE, 8, outputW, outputH, nil, 9999999 )

io.output("out/"..outfile..".design.txt"); io.write(design); io.close()
io.output("out/"..outfile..".designT.txt"); io.write(internalT); io.close()
io.output("out/"..outfile..".extra.txt"); io.write(TARGET_DEPTH); io.close()