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

out = RS.connect{ input = harrisOut, toModule =
  RS.RV(RS.modules.filterSeq{ type = FILTER_TYPE, size={W,H}, rate=1/128, fifoSize = 512 }) }

out = RS.fifo{ input = out, depth = 512, fifoList = fifoList }

-----------------------------------
branch0, branch1 = RS.fanOut{ input = out, branches = 2 }
-----------------------------------
-- branch 0
--local inp_pos = C.fifo( fifos, statements, FILTER_TYPE, branch0, 1, "p0", true) -- fifo size can also be 1 (tested in SW)
pos = RS.index{ input = branch0, key = 1 }
pos = RS.fifo{ input = pos, depth = 1024, fifoList = fifoList }

-----------------------------------
-- branch 1
--local inp_dxdy = C.fifo( fifos, statements, FILTER_TYPE, branch1, 1, "p1", true) -- fifo size can also be 1 (tested in SW)

local dxdy = RS.index{ input = branch1, key = 0 }

local dxdyTile = RS.connect{ input = dxdy, toModule = RS.RV( descriptor.tile(TILES_X*4,TILES_Y*4,4,DXDY_TYPE) ) }
local dxdy = RS.connect{ input = dxdyTile, toModule = RS.RV( RS.modules.changeRate{ type = types.array2d(DXDY_TYPE,16), H=1, inputW=TILES_X*TILES_Y, outputW=1}) }
local dxdy = RS.connect{ input = dxdy, toModule = RS.RV( RS.modules.changeRate{type=DXDY_TYPE,H=1,inputW=16,outputW=1} ) }

local desc = RS.connect{ input = dxdy, toModule = RS.RV(descriptor.descriptor) }
local desc = RS.connect{ input = desc, toModule = RS.RV( RS.modules.reduceSeq{ fn = descriptor.histogramReduce, P=1/16}) }

-- it seems like we shouldn't need a FIFO here, but we do: the changeRate downstream will only be ready every 1/8 cycles.
-- We need a tiny fifo to hold the reduceseq output, to keep it from stalling. (the scheduling isn't smart enough to know
-- that reduceSeq only has an output every 16 cycles, so it can't overlap them)
local desc = RS.fifo{ input = desc, depth = 128, fifoList = fifoList }


local desc = RS.connect{ input = desc, toModule = RS.RV( RS.modules.changeRate{ type=RS.int32, H=1, inputW=8, outputW=1 } ) }

-----------------------------------
-- sum and normalize the descriptors
local branch2, branch3 = RS.fanOut{ input = desc, branches = 2 }

-----------------------------------
-- branch 2: sum of squares
local branch2 = RS.fifo{ input = branch2, depth = 256, fifoList = fifoList }

local desc_sum = RS.connect{ input = branch2, toModule = RS.RV( RS.modules.reduceSeq{fn=sift.sumPow2(RED_TYPE,RED_TYPE,RED_TYPE), P=1/(TILES_X*TILES_Y*8)} ) }

local desc_sum = R.apply("sumlift",RM.makeHandshake(sift.fixedLift(RED_TYPE)), desc_sum)

local desc_sum = R.apply("sumsqrt",RM.makeHandshake(sift.fixedSqrt(RS.float)), desc_sum)

-- duplicate
local desc_sum = RS.connect{ input = desc_sum, toModule = RS.modules.upsampleSeq{ type = RS.float, P=1, size={W,H}, scale = {TILES_X*TILES_Y*8,1} } }

-----------------------
-- branch 3: Normalize the descriptor values (depends on branch 2)
local branch3 = RS.fifo{ input = branch3, depth = 256, fifoList = fifoList }
local branch3 = RS.connect{ input = RS.fanIn{branch3,desc_sum}, toModule = descriptor.normalize }
local desc = RS.connect{ input = branch3, toModule = RS.RV( RS.modules.changeRate{ type = RS.float, H=1, inputW=1, outputW=TILES_X*TILES_Y*8}) }
--------------------
local desc = RS.connect{ input = RS.fanIn{desc,pos}, toModule = descriptor.addPos() }

local descriptorPipeline = RS.pipeline{ input = inp, output = desc, fifoList = fifoList }

RS.harness{ fn = descriptorPipeline, 
            inputFile = "boxanim_256.raw", inputSize = {W,H},
            outputFile = "featuredescriptor", outputSize = {((W*H)/FILTER_RATE)*130, 1} }
            