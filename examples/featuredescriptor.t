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

local W = 256
local H = 256

local T = 8

local FILTER_FIFO = 512
local FILTER_RATE = 128

local ITYPE = types.array2d(types.uint(8),T)
local OTYPE = types.array2d(RS.float,2)

local outputCount = ((W*H)/FILTER_RATE)*130
local outputBytes = outputCount*4

local fifos = {}
local statements = {}

local inpraw = R.input(R.Handshake(ITYPE))
local inp = R.apply("reducerate", RM.liftHandshake(RM.changeRate(types.uint(8),1,8,1)), inpraw )

---------------------
-- Make DXDY
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
  -- merge left/right

  local FILTER_TYPE = types.tuple{types.array2d(DXDY_PAIR,TILES_X*4,TILES_Y*4),types.tuple{types.uint(16),types.uint(16)}}
  local FILTER_PAIR = types.tuple{FILTER_TYPE,types.bool()}

  local out = R.apply("merge",RM.packTuple{FILTER_TYPE,types.bool()},R.tuple("MPT",{left,right},false))

  local out = R.apply("cropao", RM.makeHandshake(C.arrayop(FILTER_PAIR,1,1)), out)
  local out = R.apply("crp", RM.liftHandshake(RM.liftDecimate(RM.cropSeq(FILTER_PAIR,W+15,H+15,1,15,0,15,0))), out)
  local out = R.apply("crpidx", RM.makeHandshake(C.index(types.array2d(FILTER_PAIR,1,1),0,0)), out)
  
  ------------------------------
  -- do filterSeq
  local filterFn = RM.filterSeq(FILTER_TYPE,W,H,FILTER_RATE,FILTER_FIFO)

  local out = R.apply("FS",RM.liftHandshake(RM.liftDecimate(filterFn)),out)
  local out = C.fifo( fifos, statements, FILTER_TYPE, out, FILTER_FIFO, "fsfifo", false)

------------
  --local siftFn, descType = sift.siftKernel(dxdyType)
  --local out = R.apply("sft", siftFn, out)


  --local inp = R.input(R.Handshake(ITYPE))
  local dxdyPair = types.tuple{dxdyType,dxdyType}
  local posType = types.uint(16)
  local PTYPE = types.tuple{posType,posType}
  local sft_ITYPE = types.tuple{types.array2d(dxdyPair,TILES_X*4,TILES_Y*4),PTYPE}
  local inp_broad = R.apply("inp_broad", RM.broadcastStream(sft_ITYPE,2), out)

  local inp_pos = C.fifo( fifos, statements, sft_ITYPE, R.selectStream("i0",inp_broad,0), 1, "p0", true) -- fifo size can also be 1 (tested in SW)
  local pos = R.apply("p",RM.makeHandshake(C.index(sft_ITYPE,1)), inp_pos)
  local pos = C.fifo( fifos, statements, PTYPE, pos, 1024, "posfifo")

--  local pos = C.fifo( fifos, statements, PTYPE, pos, 1024, "p0")
  local posX = R.apply("px",RM.makeHandshake(C.index(PTYPE,0)),pos)
  local posX = C.fifo( fifos, statements, posType, posX, 1024, "pxfifo" )
  local posY = R.apply("py",RM.makeHandshake(C.index(PTYPE,1)),pos)
  local posY = C.fifo( fifos, statements, posType, posY, 1024, "pyfifo" )

  local inp_dxdy = C.fifo( fifos, statements, sft_ITYPE, R.selectStream("i1",inp_broad,1), 1, "p1", true) -- fifo size can also be 1 (tested in SW)
  local dxdy = R.apply("dxdy_kern",RM.makeHandshake(C.index(sft_ITYPE,0,0)), inp_dxdy)

--  if GRAD_INT then
--    dxdy = d.apply("dxdylower",d.makeHandshake(d.map(lowerPair(dxdyType,GRAD_TYPE,GRAD_SCALE),TILES_X*4,TILES_Y*4)), dxdy)
--    dxdyType = GRAD_TYPE
--    dxdyPair = types.tuple{GRAD_TYPE,GRAD_TYPE}
--  end

  local dxdyTile = R.apply("TLE",RM.makeHandshake(sift.tile(TILES_X*4,TILES_Y*4,4,dxdyPair)),dxdy)
  local dxdy = R.apply( "down1", RM.liftHandshake(RM.changeRate(types.array2d(dxdyPair,16),1,TILES_X*TILES_Y,1)), dxdyTile )
  local dxdy = R.apply("down1idx",RM.makeHandshake(C.index(types.array2d(types.array2d(dxdyPair,16),1),0,0)), dxdy)
  local dxdy = R.apply("down2", RM.liftHandshake(RM.changeRate(dxdyPair,1,16,1)), dxdy )
  local dxdy = R.apply("down2idx",RM.makeHandshake(C.index(types.array2d(dxdyPair,1),0,0)), dxdy)
  local descFn, descTypeRed = sift.siftDescriptor(dxdyType)
  local descType = types.float(32)
  local desc = R.apply("desc",RM.makeHandshake(descFn),dxdy)

  local desc = R.apply("rseq",RM.liftHandshake(RM.liftDecimate(RM.reduceSeq(sift.bucketReduce(descTypeRed,8),1/16)),"BUCKET"),desc)

  -- it seems like we shouldn't need a FIFO here, but we do: the changeRate downstream will only be ready every 1/8 cycles.
  -- We need a tiny fifo to hold the reduceseq output, to keep it from stalling. (the scheduling isn't smart enough to know
  -- that reduceSeq only has an output every 16 cycles, so it can't overlap them)
  local desc = C.fifo(fifos,statements,types.array2d(descTypeRed,8),desc,128,"lol",false) -- fifo size can also be 1 (tested in SW)

  local desc = R.apply("up",RM.liftHandshake(RM.changeRate(descTypeRed,1,8,1),"CR"),desc)
  local desc = R.apply("upidx",RM.makeHandshake(C.index(types.array2d(descTypeRed,1),0,0)), desc)

  -- sum and normalize the descriptors
  local desc_broad = R.apply("desc_broad", RM.broadcastStream(descTypeRed,2), desc)

  local desc0 = R.selectStream("d0_lol",desc_broad,0)
  local desc0 = C.fifo( fifos, statements, descTypeRed, desc0, 256, "d0_lol")

  local desc1 = R.selectStream("d1_lol",desc_broad,1)
  local desc1 = C.fifo( fifos, statements, descTypeRed, desc1, 256, "d1_lol")

  local desc_sum = R.apply("sum",RM.liftHandshake(RM.liftDecimate(RM.reduceSeq(sift.sumPow2(RED_TYPE,RED_TYPE,RED_TYPE),1/(TILES_X*TILES_Y*8)))),desc1)
  local desc_sum = R.apply("sumlift",RM.makeHandshake(sift.fixedLift(RED_TYPE)), desc_sum)

  local desc_sum = R.apply("sumsqrt",RM.makeHandshake(sift.fixedSqrt(descType)), desc_sum)
  local desc_sum = R.apply("DAO",RM.makeHandshake(C.arrayop(descType,1,1)), desc_sum)
  local desc_sum = R.apply("sumup",RM.upsampleXSeq( descType, 1, TILES_X*TILES_Y*8), desc_sum)
  local desc_sum = R.apply("Didx",RM.makeHandshake(C.index(types.array2d(descType,1),0,0)), desc_sum)

  local desc0 = R.apply("d0lift",RM.makeHandshake(sift.fixedLift(RED_TYPE)), desc0)
  local desc = R.apply("pt",RM.packTuple{descType,descType},R.tuple("PTT",{desc0,desc_sum},false))
  local desc = R.apply("ptt",RM.makeHandshake(sift.fixedDiv(descType)),desc)
  local desc = R.apply("DdAO",RM.makeHandshake(C.arrayop(descType,1,1)), desc)

  local desc = R.apply("repack",RM.liftHandshake(RM.changeRate(descType,1,1,TILES_X*TILES_Y*8)),desc)
  -- we now have an array of type descType[128]. Add the pos.
  local desc_pack = R.apply("dp", RM.packTuple{types.array2d(descType,TILES_X*TILES_Y*8),posType,posType},R.tuple("DPT",{desc,posX,posY},false))
  local desc = R.apply("addpos",RM.makeHandshake(sift.addDescriptorPos(descType)), desc_pack)

  --table.insert(statements,1,desc)

  --local siftfn = RM.lambda("siftd",inp,R.statements(statements),fifos)

  out = desc
-----------------
  local out = R.apply("incrate", RM.liftHandshake(RM.changeRate(descType,1,TILES_X*TILES_Y*8+2,2)), out )

  table.insert( statements, 1, out )
  local hsfn = RM.lambda( "harris", inpraw, R.statements(statements), fifos )


harness.axi( "featuredescriptor", hsfn, "boxanim_256.raw", nil, nil, ITYPE, 8, W, H, OTYPE, 2, outputCount,1)
