local R = require "rigel"
local RM = require "modules"
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local RS = require "rigelSimple"
local C = require "examplescommon"

GRAD_INT = true
GRAD_SCALE = 4 -- <2 is bad
GRAD_TYPE = types.int(8)

local sift = require "sift_core_hw"

function siftTop(W,H,T,FILTER_RATE,FILTER_FIFO,X)
  assert(type(FILTER_FIFO)=="number")
  assert(X==nil)

  local fifos = {}
  local statements = {}

  local ITYPE = types.array2d(types.uint(8),T)
  
  local inpraw = R.input(R.Handshake(ITYPE))
  local inp = R.apply("reducerate", RM.liftHandshake(RM.changeRate(types.uint(8),1,8,1)), inpraw )
  local dxdyFn, dxdyType = harris.makeDXDY(W,H)
  local DXDY_PAIR = types.tuple{dxdyType,dxdyType}

  local out = R.apply("dxdy",dxdyFn,inp)

  out = R.apply("pad", RM.liftHandshake(RM.padSeq(DXDY_PAIR, W, H, 1, 7, 8, 7, 8, {0,0})), out)

  out = R.apply("dxdyix",RM.makeHandshake(C.index(types.array2d(DXDY_PAIR,1,1),0,0)),out)

  local dxdyBroad = R.apply("dxdy_broad", RM.broadcastStream(DXDY_PAIR,2), out)

  local internalW = W+15
  local internalH = H+15

  -------------------------------
  -- right branch: make the harris bool
  local right = R.selectStream("d1",dxdyBroad,1)
  right = C.fifo( fifos, statements, DXDY_PAIR, right, 128, "rightFIFO")

  local harrisFn, harrisType = harris.makeHarrisKernel(dxdyType,dxdyType)
  local right = R.apply("harris", RM.makeHandshake(harrisFn), right)
  local right = R.apply("AO",RM.makeHandshake(C.arrayop(harrisType,1,1)), right)

  -- now stencilify the harris
  local right = R.apply( "harris_st", RM.makeHandshake(C.stencilLinebuffer(harrisType, internalW, internalH, 1,-2,0,-2,0)), right)
  local nmsFn = harris.makeNMS( harrisType, true )
  local right = R.apply("nms", RM.makeHandshake(nmsFn), right)

  -------------------------------
  -- left branch: make the dxdy int8 stencils
  local left = R.selectStream("d0",dxdyBroad,0)

  if GRAD_INT then
    print("GRAD_INT=true")
    left = R.apply("lower", RM.makeHandshake(sift.lowerPair(dxdyType,GRAD_TYPE,GRAD_SCALE)), left)
    dxdyType = GRAD_TYPE
    DXDY_PAIR = types.tuple{GRAD_TYPE,GRAD_TYPE}
  else
    print("GRAD_INT=false")
  end
  
  left = C.fifo( fifos, statements, DXDY_PAIR, left, 2048/DXDY_PAIR:verilogBits(), "leftFIFO")

  local left = R.apply("stlbinp", RM.makeHandshake(C.arrayop(DXDY_PAIR,1,1)), left)
  local left = R.apply( "stlb", RM.makeHandshake(C.stencilLinebuffer(DXDY_PAIR, internalW, internalH, 1,-TILES_X*4+1,0,-TILES_Y*4+1,0)), left)
  left = R.apply("stpos", RM.makeHandshake(sift.addPos(dxdyType,internalW,internalH,15,15)), left)
  -------------------------------


  local FILTER_TYPE = types.tuple{types.array2d(DXDY_PAIR,TILES_X*4,TILES_Y*4),types.tuple{types.uint(16),types.uint(16)}}
  local FILTER_PAIR = types.tuple{FILTER_TYPE,types.bool()}

  -- merge left/right
  local out = R.apply("merge",RM.packTuple{FILTER_TYPE,types.bool()},R.tuple("MPT",{left,right},false))

  local out = R.apply("cropao", RM.makeHandshake(C.arrayop(FILTER_PAIR,1,1)), out)
  local out = R.apply("crp", RM.liftHandshake(RM.liftDecimate(RM.cropSeq(FILTER_PAIR,W+15,H+15,1,15,0,15,0))), out)
  local out = R.apply("crpidx", RM.makeHandshake(C.index(types.array2d(FILTER_PAIR,1,1),0,0)), out)
  
  local filterFn = RM.filterSeq(FILTER_TYPE,W,H,FILTER_RATE,FILTER_FIFO)

  local out = R.apply("FS",RM.liftHandshake(RM.liftDecimate(filterFn)),out)
  local out = C.fifo( fifos, statements, FILTER_TYPE, out, FILTER_FIFO, "fsfifo", false)

  local siftFn, descType = sift.siftKernel(dxdyType)
  local out = R.apply("sft", siftFn, out)
  local out = R.apply("incrate", RM.liftHandshake(RM.changeRate(descType,1,TILES_X*TILES_Y*8+2,2)), out )

  table.insert( statements, 1, out )
  local fn = RM.lambda( "harris", inpraw, R.statements(statements), fifos )

  return fn, descType
end


local W = 256
local H = 256

local T = 8

local FILTER_FIFO = 512
local FILTER_RATE = 128

local ITYPE = types.array2d(types.uint(8),T)
local siftFn, siftType = siftTop(W,H,T,FILTER_RATE,FILTER_FIFO)
local OTYPE = types.array2d(siftType,2)

local outputCount = ((W*H)/FILTER_RATE)*130
local outputBytes = outputCount*4
local hsfn = siftFn


harness.axi( "featuredetector", hsfn, "boxanim_256.raw", nil, nil, ITYPE, 8, W, H, OTYPE, 2, outputCount,1)
