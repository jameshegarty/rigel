local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"
local P = require "pyramid_core"

T = 8 -- throughput
A = types.uint(8)

local ConvWidth = 8

local inputW = 128
local inputH = 64

local TARGET_DEPTH = string.sub(arg[0],string.find(arg[0],"%d+"))
TARGET_DEPTH = tonumber(TARGET_DEPTH)



--local convolvefn = C.convolveConstant( types.uint(8), ConvWidth, rep(1,ConvWidth*ConvWidth), 6 )

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
  local PI = P.pyramidIter(depth,depth>1,curT,curW,curH,ConvWidth)
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
  local TOP_TYPE = types.array2d(A,T)
  if depth==TARGET_DEPTH then
    if curT~=8 then
      -- we must do the changerate _before_ the fifo, or the things later will run at 1/2 rate we expect
      out = d.apply("CR"..depth,d.liftHandshake(d.changeRate(A,1,curT,8)), out)
    end

    -- last level
    out = P.FIFO(fifos,statements,TOP_TYPE, out)

    L[depth] = out

  else
    print("curT",curT)
    out= d.apply("out_broadcast"..depth, d.broadcastStream(THIS_TYPE,2), out)
    out0 = P.FIFO(fifos,statements,THIS_TYPE,d.selectStream("i0"..depth,out,0))

    if curT<8 then
      out1 = d.apply("CR"..depth,d.liftHandshake(d.changeRate(A,1,curT,8)), d.selectStream("i1"..depth,out,1))
    else
      out1 = d.selectStream("i1"..depth,out,1)
    end

    out1 = P.FIFO(fifos,statements,TOP_TYPE, out1)

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