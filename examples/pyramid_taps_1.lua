local R = require "rigel"
local RM = require "modules"
local RS = require "rigelSimple"
local types = require("types")
local harness = require "harness"
local C = require "examplescommon"
local P = require "pyramid_core"
local SDFRate = require "sdfrate"
local J = require "common"

internalT = 4 -- internal throughput
outputT = 8
A = types.uint(8)

local LARGE = string.find(arg[0],"large")
LARGE = (LARGE~=nil)
local NOFIFO = string.find(arg[0],"nofifo")
NOFIFO = (NOFIFO~=nil)

local TARGET_DEPTH = string.sub(arg[0],string.find(arg[0],"%d+"))
TARGET_DEPTH = tonumber(TARGET_DEPTH)

local ConvWidth = 8

local inputW = 64
local inputH = 32

-- 64x32 is too small
if TARGET_DEPTH==4 then inputW, inputH = 128,64 end

if LARGE then
  inputW, inputH = 384, 384
end


local TAP_TYPE = types.array2d( types.uint(8), ConvWidth, ConvWidth ):makeConst()
local DATA_TYPE = types.array2d(A,8)
local HST = types.tuple{DATA_TYPE,TAP_TYPE}

local inp = R.input( R.Handshake(HST) )
local inpList = J.pack(RS.fanOut{input=inp,branches=1+TARGET_DEPTH})
local out = R.apply("idx0",RM.makeHandshake(C.index(HST,0)),inpList[1])

if internalT<8 then
  out = R.apply("CRtop",RM.liftHandshake(RM.changeRate(A,1,8,internalT)), out)
end

--curT = internalT
curW = inputW
curH = inputH
local L = {}
local SDF = {}

local outputW = 0
local outputH = inputH/math.pow(2,TARGET_DEPTH-1)

local fifos = {}
local statements = {}


for depth=1,TARGET_DEPTH do

  local PI = P.pyramidIterTaps( depth, depth>1, internalT, curW, curH, ConvWidth, NOFIFO, true )

  local tapinp =  R.apply("idx1_"..tostring(depth),RM.makeHandshake(C.index(HST,1)),inpList[1+depth])

  local CCT = R.concat("CONVPIPEINP"..depth,{out,tapinp})
  local piinp = R.apply("CPI"..depth, RM.packTuple({types.array2d(A,internalT),TAP_TYPE}), CCT)
  out = R.apply("p"..depth, PI, piinp)

  local thisW = inputW*inputH/math.pow(4,depth-1)
  --print("thisW",thisW,thisW/outputH)
  outputW = outputW + thisW/outputH

  if depth>1 then
    --curT = internalT/4 -- we do changeRate so that this is always true for this implementation
    curW = curW/2
    curH = curH/2
  end

  --local THIS_TYPE = types.array2d(types.uint(8),curT)
  local TOP_TYPE = types.array2d(A,internalT)
  local OUT_TYPE = types.array2d(A,8)
  if depth==TARGET_DEPTH then

    -- we must do the changerate _before_ the fifo, or the things later will run at 1/2 rate we expect
    out = R.apply("CR"..depth,RM.liftHandshake(RM.changeRate(A,1,internalT,8)), out)

    -- last level
    out = P.FIFO(fifos,statements,OUT_TYPE, out,nil, "finalFIFO", curW, curH, 8 )
    L[depth] = out
  else
    out = R.apply("out_broadcast"..depth, RM.broadcastStream(TOP_TYPE,2), out)
    local out0 = R.selectStream("i0"..depth,out,0)
    out0 = P.FIFO( fifos, statements, TOP_TYPE, out0, nil, "internal"..depth, curW, curH, internalT )

    local out1 = R.apply("CRr"..depth,RM.liftHandshake(RM.changeRate(A,1,internalT,8)), R.selectStream("i1"..depth,out,1) )
    out1 = P.FIFO( fifos, statements, OUT_TYPE, out1, nil, "output"..depth, curW, curH, 8 )

    L[depth] = out1
    out = out0
  end


  SDF[depth] = {1,math.pow(4,depth-1)}
--  SDF[depth] = {PI.sdfOutput[1][1],PI.sdfOutput[1][2]}
--  if depth>1 then SDF[depth][1] = SDF[depth][1]/2 end
end

--print("outputW",outputW,"outputH",outputH)

--for k,v in ipairs(SDF) do print("SDF",v[1],v[2]) end
SDF = SDFRate.normalize(SDF)
--for k,v in ipairs(SDF) do print("SDF",v[1],v[2]) end

local RW_TYPE = types.array2d( types.uint(8), 8 ) -- simulate axi bus

--print("TARGET_DEPTH",TARGET_DEPTH)
if TARGET_DEPTH>1 then
  SER = RM.serialize( RW_TYPE, SDF, RM.pyramidSchedule( TARGET_DEPTH, inputW, outputT ) ) 
  out = R.apply("toHandshakeArray", RM.toHandshakeArrayOneHot( RW_TYPE, SDF), R.concatArray2d( "sa", L, TARGET_DEPTH, 1))
  out = R.apply("ser", SER, out )

  out = R.apply("flatten", RM.flattenStreams(RW_TYPE, SDF), out )
end

if outputT~=8 then
  out = R.apply("CRend",RM.liftHandshake(RM.changeRate(A,1,outputT,8)), out)
end

table.insert(statements,1,out)

hsfn = RM.lambda("pyramid", inp, R.statements(statements), fifos )

local scale = math.pow(2,TARGET_DEPTH-1)

local infile = "frame_64.raw"
local outfile = "pyramid_taps_"..tostring(TARGET_DEPTH)
local design = "Gaussian Pyramid 64"
if TARGET_DEPTH==4 then infile, design = "frame_128.raw","Gaussian Pyramid 128" end

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

harness{ outFile=outfile, fn=hsfn, inFile=infile, tapType=TAP_TYPE, tapValue=P.G, inSize={inputW,inputH}, outSize={outputW,outputH}, earlyOverride=9999999 }

io.output("out/"..outfile..".design.txt"); io.write(design); io.close()
io.output("out/"..outfile..".designT.txt"); io.write(internalT); io.close()
io.output("out/"..outfile..".extra.txt"); io.write(TARGET_DEPTH); io.close()
