local R = require "rigel"
local RM = require "modules"
local types = require("types")
--local S = require("systolic")
--local harness = require "harness"
local RS = require "rigelSimple"
local C = require "examplescommon"
local harris = require "harris_core"

local descriptor = require "descriptor_core"

local sift = require "sift_core_hw"

local W = 256
local H = 256

local FILTER_FIFO = 512
local FILTER_RATE = 128

local fifoList = {}

local inp = RS.input(RS.RV(RS.array(RS.uint8,1)))


local harrisOut = RS.connect{ input = inp, toModule = harris.harrisWithStencil{W=W,H=H} }
  
-----------------------------------
-- filterSeq
local DXDY_TYPE = RS.tuple{ RS.int8, RS.int8 }
local POS_TYPE = RS.tuple{ RS.uint16, RS.uint16 }
local FILTER_TYPE = RS.tuple{ RS.array2d( DXDY_TYPE, TILES_X*4, TILES_Y*4 ), POS_TYPE }

local out = RS.connect{ input = harrisOut, toModule =
  RS.RV(RS.modules.filterSeq{ type = FILTER_TYPE, size={W,H}, rate=1/128, fifoSize = 512 }) }

local out = RS.fifo{ input = out, depth = 512, fifoList = fifoList }

-----------------------------------
local branch0, branch1 = RS.fanOut{ input = out, branches = 2 }
-----------------------------------
-- branch 0
--local inp_pos = C.fifo( fifos, statements, FILTER_TYPE, branch0, 1, "p0", true) -- fifo size can also be 1 (tested in SW)
local pos = RS.index{ input = branch0, key = 1 }
local pos = RS.fifo{ input = pos, depth = 1024, fifoList = fifoList }

-----------------------------------
-- branch 1
--local inp_dxdy = C.fifo( fifos, statements, FILTER_TYPE, branch1, 1, "p1", true) -- fifo size can also be 1 (tested in SW)

local dxdy = RS.index{ input = branch1, key = 0 }

local dxdyTile = RS.connect{ input = dxdy, toModule = RS.RV( descriptor.tile(TILES_X*4,TILES_Y*4,4,DXDY_TYPE) ) }
local dxdy = RS.connect{ input = dxdyTile, toModule = RS.RV( RS.modules.changeRate{ type = types.array2d(DXDY_TYPE,16), H=1, inputW=TILES_X*TILES_Y, outputW=1}) }
local dxdy = RS.connect{ input = dxdy, toModule = RS.RV( RS.modules.changeRate{type=DXDY_TYPE,H=1,inputW=16,outputW=1} ) }

local descTypeRed = types.int(32)
local descType = types.float(32)

local desc = RS.connect{ input = dxdy, toModule = RS.RV(descriptor.descriptor) }

local desc = RS.connect{ input = desc, toModule = RS.RV( RS.modules.reduceSeq{ fn = descriptor.histogramReduce, P=1/16}) }

-- it seems like we shouldn't need a FIFO here, but we do: the changeRate downstream will only be ready every 1/8 cycles.
-- We need a tiny fifo to hold the reduceseq output, to keep it from stalling. (the scheduling isn't smart enough to know
-- that reduceSeq only has an output every 16 cycles, so it can't overlap them)
local desc = RS.fifo{ input = desc, depth = 128, fifoList = fifoList }

local desc = R.apply("up",RM.liftHandshake(RM.changeRate(descTypeRed,1,8,1),"CR"),desc)
local desc = R.apply("upidx",RM.makeHandshake(C.index(types.array2d(descTypeRed,1),0,0)), desc)

-- sum and normalize the descriptors
local desc_broad = R.apply("desc_broad", RM.broadcastStream(descTypeRed,2), desc)

-----------------------
-- branch 2: sum of squares
local desc1 = R.selectStream("d1_lol",desc_broad,1)
local desc1 = RS.fifo{ input = desc1, depth = 256, fifoList = fifoList }

local desc_sum = R.apply("sum",RM.liftHandshake(RM.liftDecimate(RM.reduceSeq(sift.sumPow2(RED_TYPE,RED_TYPE,RED_TYPE),1/(TILES_X*TILES_Y*8)))),desc1)
local desc_sum = R.apply("sumlift",RM.makeHandshake(sift.fixedLift(RED_TYPE)), desc_sum)

local desc_sum = R.apply("sumsqrt",RM.makeHandshake(sift.fixedSqrt(descType)), desc_sum)
local desc_sum = R.apply("DAO",RM.makeHandshake(C.arrayop(descType,1,1)), desc_sum)
-- duplicate
local desc_sum = R.apply("sumup",RM.upsampleXSeq( descType, 1, TILES_X*TILES_Y*8), desc_sum)
local desc_sum = R.apply("Didx",RM.makeHandshake(C.index(types.array2d(descType,1),0,0)), desc_sum)

--------------------
-- branch 3: Normalize the descriptor values (depends on branch 2)
local desc0 = R.selectStream("d0_lol",desc_broad,0)
local desc0 = RS.fifo{ input = desc0, depth = 256, fifoList = fifoList }

local desc0 = R.apply("d0lift",RM.makeHandshake(sift.fixedLift(RED_TYPE)), desc0)
local desc = R.apply("pt",RM.packTuple{descType,descType},R.tuple("PTT",{desc0,desc_sum},false))
local desc = R.apply("ptt",RM.makeHandshake(sift.fixedDiv(descType)),desc)
local desc = R.apply("DdAO",RM.makeHandshake(C.arrayop(descType,1,1)), desc)

local desc = R.apply("repack",RM.liftHandshake(RM.changeRate(descType,1,1,TILES_X*TILES_Y*8)),desc)

-----------------
local desc = RS.connect{ input = RS.fanIn{desc,pos}, toModule = descriptor.addPos() }

local descriptorPipeline = RS.pipeline{ input = inp, output = desc, fifoList = fifoList }

RS.harness{ fn = descriptorPipeline, 
            inputFile = "boxanim_256.raw", inputSize = {W,H},
            outputFile = "featuredescriptor", outputSize = {((W*H)/FILTER_RATE)*130, 1} }
            