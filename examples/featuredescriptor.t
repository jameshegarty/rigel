local RS = require "rigelSimple"
local harris = require "harris_core"
local descriptor = require "descriptor_core"

W, H = 256, 256
TILES_X, TILES_Y = 4, 4

local FILTER_FIFO = 512
local FILTER_RATE = 128

local fifoList = {}

-----------------------------------
-- Start of pipeline: apply harris
inp = RS.input(RS.RV(RS.array(RS.uint8,1)))
harrisOut = RS.connect{ input = inp, toModule = harris.harrisWithStencil{W=W,H=H} }
  
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

dxdy = RS.index{ input = branch1, key = 0 }

dxdyTile = RS.connect{ input = dxdy, toModule = RS.RV( descriptor.tile(TILES_X*4,TILES_Y*4,4,DXDY_TYPE) ) }
dxdy = RS.connect{ input = dxdyTile, toModule = RS.RV( RS.modules.changeRate{ type = RS.array(DXDY_TYPE,16), H=1, inputW=TILES_X*TILES_Y, outputW=1}) }
dxdy = RS.connect{ input = dxdy, toModule = RS.RV( RS.modules.changeRate{type=DXDY_TYPE,H=1,inputW=16,outputW=1} ) }

desc = RS.connect{ input = dxdy, toModule = RS.RV(descriptor.descriptor) }
desc = RS.connect{ input = desc, toModule = RS.RV( RS.modules.reduceSeq{ fn = descriptor.histogramReduce, P=1/16}) }

desc = RS.fifo{ input = desc, depth = 128, fifoList = fifoList }


desc = RS.connect{ input = desc, toModule = RS.RV( RS.modules.changeRate{ type=RS.int32, H=1, inputW=8, outputW=1 } ) }

-----------------------------------
-- sum and normalize the descriptors
branch2, branch3 = RS.fanOut{ input = desc, branches = 2 }

-----------------------------------
-- branch 2: sum of squares
branch2 = RS.fifo{ input = branch2, depth = 256, fifoList = fifoList }

desc_sum = RS.connect{ input = branch2, toModule = 
  RS.RV( RS.modules.reduceSeq{fn=RS.modules.sumPow2{inputType=RED_TYPE,outputType=RED_TYPE}, P=1/(TILES_X*TILES_Y*8)} ) }

desc_sum = RS.connect{ input = desc_sum, toModule = RS.RV(RS.modules.sqrt{ inputType = RED_TYPE, outputType = RS.float }) }

-- duplicate
desc_sum = RS.connect{ input = desc_sum, toModule = RS.modules.upsampleSeq{ type = RS.float, P=1, size={W,H}, scale = {TILES_X*TILES_Y*8,1} } }

-----------------------------------
-- branch 3: Normalize the descriptor values (depends on branch 2)
branch3 = RS.fifo{ input = branch3, depth = 256, fifoList = fifoList }
branch3 = RS.connect{ input = RS.fanIn{branch3,desc_sum}, toModule = descriptor.normalize }
desc = RS.connect{ input = branch3, toModule = RS.RV( RS.modules.changeRate{ type = RS.float, H=1, inputW=1, outputW=TILES_X*TILES_Y*8}) }

-----------------------------------
-- merge branch 2 and 3
desc = RS.connect{ input = RS.fanIn{desc,pos}, toModule = descriptor.addPos() }
-----------------------

descriptorPipeline = RS.pipeline{ input = inp, output = desc, fifoList = fifoList }

RS.harness{ fn = descriptorPipeline, 
            inputFile = "boxanim_256.raw", inputSize = {W,H},
            outputFile = "featuredescriptor", outputSize = {((W*H)/FILTER_RATE)*130, 1} }
            