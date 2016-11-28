local R = require "rigel"
local RM = require "modules"
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local RS = require "rigelSimple"
local C = require "examplescommon"
local harris = require "harris_core"

local descriptor = require "descriptor_core"

local sift = require "sift_core_hw"

local W = 256
local H = 256

local FILTER_FIFO = 512
local FILTER_RATE = 128

local ITYPE = types.array2d(types.uint(8),1)


local fifos = {}
local statements = {}

local inp = R.input(R.Handshake(ITYPE))


local harrisOut = RS.connect{ input = inp, toModule = harris.harrisWithStencil{W=W,H=H} }
  
------------------------------
-- filterSeq
local DXDY_TYPE = RS.tuple{ RS.int8, RS.int8 }
local POS_TYPE = RS.tuple{ RS.uint16, RS.uint16 }
local FILTER_TYPE = RS.tuple{ RS.array2d( DXDY_TYPE, TILES_X*4, TILES_Y*4 ), POS_TYPE }

local out = RS.connect{ input = harrisOut, toModule =
  RS.RV(RS.modules.filterSeq{ type = FILTER_TYPE, size={W,H}, rate=1/128, fifoSize = 512 }) }

local out = C.fifo( fifos, statements, FILTER_TYPE, out, FILTER_FIFO, "fsfifo", false)

------------
local branch0, branch1 = RS.fanOut{ input = out, branches = 2 }
-----------------------------------
-- branch 0
local inp_pos = C.fifo( fifos, statements, FILTER_TYPE, branch0, 1, "p0", true) -- fifo size can also be 1 (tested in SW)
local pos = R.apply("p",RM.makeHandshake(C.index(FILTER_TYPE,1)), inp_pos)
local pos = C.fifo( fifos, statements, POS_TYPE, pos, 1024, "posfifo")


local posX = R.apply("px",RM.makeHandshake(C.index(POS_TYPE,0)),pos)
local posX = C.fifo( fifos, statements, RS.uint16, posX, 1024, "pxfifo" )
local posY = R.apply("py",RM.makeHandshake(C.index(POS_TYPE,1)),pos)
local posY = C.fifo( fifos, statements, RS.uint16, posY, 1024, "pyfifo" )

-----------------------------------
-- branch 1
local inp_dxdy = C.fifo( fifos, statements, FILTER_TYPE, branch1, 1, "p1", true) -- fifo size can also be 1 (tested in SW)
local dxdy = R.apply("dxdy_kern",RM.makeHandshake(C.index(FILTER_TYPE,0,0)), inp_dxdy)

local dxdyTile = R.apply("TLE",RM.makeHandshake(sift.tile(TILES_X*4,TILES_Y*4,4,DXDY_TYPE)),dxdy)
local dxdy = R.apply( "down1", RM.liftHandshake(RM.changeRate(types.array2d(DXDY_TYPE,16),1,TILES_X*TILES_Y,1)), dxdyTile )
local dxdy = R.apply("down1idx",RM.makeHandshake(C.index(types.array2d(types.array2d(DXDY_TYPE,16),1),0,0)), dxdy)
local dxdy = R.apply("down2", RM.liftHandshake(RM.changeRate(DXDY_TYPE,1,16,1)), dxdy )
local dxdy = R.apply("down2idx",RM.makeHandshake(C.index(types.array2d(DXDY_TYPE,1),0,0)), dxdy)
local descFn, descTypeRed = sift.siftDescriptor(GRAD_TYPE)
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


  -----------------------
  -- branch 0: sum of squares
  local desc1 = R.selectStream("d1_lol",desc_broad,1)
  local desc1 = C.fifo( fifos, statements, descTypeRed, desc1, 256, "d1_lol")

  local desc_sum = R.apply("sum",RM.liftHandshake(RM.liftDecimate(RM.reduceSeq(sift.sumPow2(RED_TYPE,RED_TYPE,RED_TYPE),1/(TILES_X*TILES_Y*8)))),desc1)
  local desc_sum = R.apply("sumlift",RM.makeHandshake(sift.fixedLift(RED_TYPE)), desc_sum)

  local desc_sum = R.apply("sumsqrt",RM.makeHandshake(sift.fixedSqrt(descType)), desc_sum)
  local desc_sum = R.apply("DAO",RM.makeHandshake(C.arrayop(descType,1,1)), desc_sum)
  -- duplicate
  local desc_sum = R.apply("sumup",RM.upsampleXSeq( descType, 1, TILES_X*TILES_Y*8), desc_sum)
  local desc_sum = R.apply("Didx",RM.makeHandshake(C.index(types.array2d(descType,1),0,0)), desc_sum)

  --------------------
  -- branch 1: (depends on branch 0). Normalize the descriptor values
  local desc0 = R.selectStream("d0_lol",desc_broad,0)
  local desc0 = C.fifo( fifos, statements, descTypeRed, desc0, 256, "d0_lol")

  local desc0 = R.apply("d0lift",RM.makeHandshake(sift.fixedLift(RED_TYPE)), desc0)
  local desc = R.apply("pt",RM.packTuple{descType,descType},R.tuple("PTT",{desc0,desc_sum},false))
  local desc = R.apply("ptt",RM.makeHandshake(sift.fixedDiv(descType)),desc)
  local desc = R.apply("DdAO",RM.makeHandshake(C.arrayop(descType,1,1)), desc)

  local desc = R.apply("repack",RM.liftHandshake(RM.changeRate(descType,1,1,TILES_X*TILES_Y*8)),desc)

  -----------------
  -- we now have an array of type descType[128]. Add the pos.
  local desc_pack = R.apply("dp", RM.packTuple{types.array2d(descType,TILES_X*TILES_Y*8),RS.uint16,RS.uint16},R.tuple("DPT",{desc,posX,posY},false))
  local desc = R.apply("addpos",RM.makeHandshake(sift.addDescriptorPos(descType)), desc_pack)

  --table.insert(statements,1,desc)

  --local siftfn = RM.lambda("siftd",inp,R.statements(statements),fifos)

  out = desc
-----------------
  local out = R.apply("incrate", RM.liftHandshake(RM.changeRate(descType,1,TILES_X*TILES_Y*8+2,2)), out )

  table.insert( statements, 1, out )
  local hsfn = RM.lambda( "harris", inp, R.statements(statements), fifos )


--local outputCount = 
--local outputBytes = outputCount*4

--harness.axi( "featuredescriptor", hsfn, "boxanim_256.raw", nil, nil, ITYPE, 8, W, H, OTYPE, 2, outputCount,1)
RS.harness{ fn = hsfn, 
            inputFile = "boxanim_256.raw", inputSize = {W,H},
            outputFile = "featuredescriptor", outputSize = {((W*H)/FILTER_RATE)*130, 1} }
            