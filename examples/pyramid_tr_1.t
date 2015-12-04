local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"
local P = require "pyramid_core"

T = 4 -- throughput
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
--local out = d.apply("CRtop",d.liftHandshake(d.changeRate(A,1,8,T)), inp)
local out = d.apply("idx0",d.makeHandshake(d.index(HST,0)),inp)
if T<8 then
  out = d.apply("CRtop",d.liftHandshake(d.changeRate(A,1,8,T)), out)
end

local tapinp =  d.apply("idx1",d.makeHandshake(d.index(HST,1)),inp)

curT = T
--vecT = T
curW = inputW
curH = inputH
local L = {}
local SDF = {}

local outputW = 0
local outputH = inputH/math.pow(2,TARGET_DEPTH-1)

local fifos = {}
local statements = {}

for depth=1,TARGET_DEPTH do
  print("DODEPTH",depth,"T",curT)
  local PI

  if curT>1 then
    PI = P.pyramidIterTaps(depth,depth>1,curT,curW,curH,ConvWidth,NOFIFO,false)
    local piinp = d.apply("CPI"..depth, darkroom.packTuple({types.array2d(A,curT),TAP_TYPE}), d.tuple("CONVPIPEINP"..depth,{out,tapinp},false))
    out = d.apply("p"..depth, PI, piinp)
  else
    PI = P.pyramidIterTR(depth,curT,curW,curH,ConvWidth,NOFIFO)
    out = d.apply("p"..depth, PI, out)
  end

  print("PI",PI.inputType,PI.outputType)
  print(PI.sdfInput[1][1],PI.sdfInput[1][2])
  print(PI.sdfOutput[1][1],PI.sdfOutput[1][2])

  local thisW = inputW*inputH/math.pow(4,depth-1)
  print("thisW",thisW,thisW/outputH)
  outputW = outputW + thisW/outputH

  if depth>1 then
    curT = curT/4
--    vecT = vecT/2
    curW = curW/2
    curH=curH/2
  end

  local THIS_TYPE = types.array2d( types.uint(8), math.max(curT,1) )
  local TOP_TYPE = types.array2d(A,T)
  local OUT_TYPE = types.array2d(A,8)
  if depth==TARGET_DEPTH then
    if curT<outputT then
      -- we must do the changerate _before_ the fifo, or the things later will run at 1/2 rate we expect
      out = d.apply("CR"..depth,d.liftHandshake(d.changeRate(A,1,math.max(curT,1),8)), out)
    end

    -- last level
    out = P.FIFO(fifos,statements,OUT_TYPE, out, nil, "final", curW, curH, 8)

    L[depth] = out

  else
    print("curT",curT)
    out= d.apply("out_broadcast"..depth, d.broadcastStream(THIS_TYPE,2), out)
    out0 = P.FIFO(fifos,statements,THIS_TYPE,d.selectStream("i0"..depth,out,0),nil,"internal"..depth,curW,curH,math.max(curT,1))

    if curT<8 then
      out1 = d.apply("CR"..depth,d.liftHandshake(d.changeRate(A,1,math.max(curT,1),8)), d.selectStream("i1"..depth,out,1))
    else
      out1 = d.selectStream("i1"..depth,out,1)
    end

    -- due to the downsample in Y, we actually have to halve the vector size by another 2x
--    if curT>=1 and curT<8 then
--      out0 = d.apply("CRb"..depth,d.liftHandshake(d.changeRate(A,1,vecT,curT)), out0)
-- ******************
--      vecT = curT 
--    end


    out1 = P.FIFO(fifos,statements,OUT_TYPE, out1,nil,"output"..depth,curW,curH,8)

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
local RW_TYPE = types.array2d( types.uint(8), 8 ) -- simulate axi bus
if TARGET_DEPTH>1 then
  SER = darkroom.serialize( RW_TYPE, SDF, d.pyramidSchedule( TARGET_DEPTH, inputW, outputT ) ) 
  out = darkroom.apply("toHandshakeArray", d.toHandshakeArray( RW_TYPE, SDF), d.array2d( "sa", L, TARGET_DEPTH, 1, false))
  out = darkroom.apply("ser", SER, out )
--local out = darkroom.apply("demux", darkroom.demux(RW_TYPE, d.sdfNormalize(SDF)), out )
  out = d.apply("flatten", d.flattenStreams(RW_TYPE, SDF), out )
end

--out = d.apply("CRbot",d.liftHandshake(d.changeRate(A,1,T,8)), out)

--if T~=8 then
--  out = d.apply("CRend",d.liftHandshake(d.changeRate(A,1,T,8)), out)
--end

table.insert(statements,1,out)

hsfn = darkroom.lambda("pyramid", inp, d.statements(statements), fifos )

local scale = math.pow(2,TARGET_DEPTH-1)

local IO_TYPE = types.array2d( types.uint(8), 8 ) -- simulate axi bus

local infile = "frame_128.raw"
local outfile = "pyramid_tr_"..tostring(TARGET_DEPTH)
local design = "Gaussian Pyramid TR 128"

if LARGE then
  infile = "frame_384_384.raw"
  if NOFIFO then
    outfile = "pyramid_large_nofifo_tr_"..tostring(TARGET_DEPTH)
    design = "Gaussian Pyramid TR NOFIFO 384"
  else
    outfile = "pyramid_large_tr_"..tostring(TARGET_DEPTH)
    design = "Gaussian Pyramid TR 384"
  end
end


harness.axi( outfile, hsfn, infile, TAP_TYPE, P.G, IO_TYPE, 8, inputW, inputH, IO_TYPE, 8, outputW, outputH, nil, 9999999 )

io.output("out/"..outfile..".design.txt"); io.write(design); io.close()
io.output("out/"..outfile..".designT.txt"); io.write(T); io.close()
io.output("out/"..outfile..".extra.txt"); io.write(TARGET_DEPTH); io.close()