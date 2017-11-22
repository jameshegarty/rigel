local R = require "rigel"
local RM = require "modules"
local RS = require "rigelSimple"
local types = require("types")
local harness = require "harness"
local C = require "examplescommon"
local P = require "pyramid_core"
local SDFRate = require "sdfrate"
local J = require "common"

T = 4 -- throughput
outputT = 8
A = types.uint(8)

local LARGE = string.find(arg[0],"large")
LARGE = (LARGE~=nil)
local NOFIFO = string.find(arg[0],"nofifo")
NOFIFO = (NOFIFO~=nil)

local ConvWidth = 8

local TARGET_DEPTH = string.sub(arg[0],string.find(arg[0],"%d+"))
TARGET_DEPTH = tonumber(TARGET_DEPTH)

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
local inp0, inp1 = RS.fanOut{input=inp,branches=2}

local out = R.apply("idx0", RM.makeHandshake( C.index(HST,0)),inp0)
if T<8 then
  out = R.apply("CRtop", RM.liftHandshake( RM.changeRate(A,1,8,T)), out)
end

local totT = 0
local totTT = T
for depth=1,TARGET_DEPTH do
  if totTT>1 then  totT=totT+1 end
  if depth>1 then totTT=totTT/4; end
end

local tapinp =  R.apply("idx1", RM.makeHandshake( C.index(HST,1)),inp1)
--print("TOT",totT)
local tapinpL = J.pack(RS.fanOut{input=tapinp, branches=totT})
  
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
  local PI

  if curT>1 then
    PI = P.pyramidIterTaps(depth,depth>1,curT,curW,curH,ConvWidth,NOFIFO,false)
    local piinp = R.apply("CPI"..depth, RM.packTuple({types.array2d(A,curT),TAP_TYPE}), R.concat("CONVPIPEINP"..depth,{out,tapinpL[depth]}))
    out = R.apply("p"..depth, PI, piinp)
  else
    PI = P.pyramidIterTR(depth,curT,curW,curH,ConvWidth,NOFIFO)
    out = R.apply("p"..depth, PI, out)
  end

  local thisW = inputW*inputH/math.pow(4,depth-1)

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
      out = R.apply("CR"..depth, RM.liftHandshake( RM.changeRate(A,1,math.max(curT,1),8)), out)
    end

    -- last level
    out = P.FIFO(fifos,statements,OUT_TYPE, out, nil, "finalFIFO", curW, curH, 8)

    L[depth] = out

  else
    out= R.apply("out_broadcast"..depth, RM.broadcastStream(THIS_TYPE,2), out)
    out0 = P.FIFO(fifos,statements,THIS_TYPE,R.selectStream("i0"..depth,out,0),nil,"internal"..depth,curW,curH,math.max(curT,1))

    if curT<8 then
      out1 = R.apply("CR"..depth, RM.liftHandshake( RM.changeRate(A,1,math.max(curT,1),8)), R.selectStream("i1"..depth,out,1))
    else
      out1 = R.selectStream("i1"..depth,out,1)
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


SDF = SDFRate.normalize(SDF)

local RW_TYPE = types.array2d( types.uint(8), 8 ) -- simulate axi bus
if TARGET_DEPTH>1 then
  SER = RM.serialize( RW_TYPE, SDF, RM.pyramidSchedule( TARGET_DEPTH, inputW, outputT ) ) 
  out = R.apply("toHandshakeArray", RM.toHandshakeArrayOneHot( RW_TYPE, SDF), R.concatArray2d( "sa", L, TARGET_DEPTH, 1))
  out = R.apply("ser", SER, out )

  out = R.apply("flatten", RM.flattenStreams(RW_TYPE, SDF), out )
end

table.insert(statements,1,out)

hsfn = RM.lambda("pyramid", inp, R.statements(statements), fifos )

local scale = math.pow(2,TARGET_DEPTH-1)

local IO_TYPE = types.array2d( types.uint(8), 8 ) -- simulate axi bus

local infile = "frame_64.raw"
local outfile = "pyramid_tr_"..tostring(TARGET_DEPTH)
local design = "Gaussian Pyramid TR 64"
if TARGET_DEPTH==4 then infile, design = "frame_128.raw","Gaussian Pyramid 128" end

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


harness{ outFile=outfile, fn=hsfn, inFile=infile, tapType=TAP_TYPE, tapValue=P.G, inSize={inputW,inputH}, outSize={outputW,outputH}, earlyOverride=9999999}

io.output("out/"..outfile..".design.txt"); io.write(design); io.close()
io.output("out/"..outfile..".designT.txt"); io.write(T); io.close()
io.output("out/"..outfile..".extra.txt"); io.write(TARGET_DEPTH); io.close()
