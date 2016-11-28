local R = require "rigelSimple"
local harris = require "harris_core"
local descriptor = require "descriptor_core"

W, H = 256, 256
TILES_X, TILES_Y = 4, 4

local FILTER_FIFO = 512
local FILTER_RATE = 1/128

local fifoList = {}

-----------------------------------
-- Start of pipeline: apply harris
inp = R.input(R.RV(R.array(R.uint8,1)))
harrisOut = R.connect{ input = inp, toModule = harris.harrisWithStencil{W=W,H=H} }
  
-----------------------------------
-- filterSeq
DXDY_TYPE = R.tuple{ R.int8, R.int8 }
POS_TYPE = R.tuple{ R.uint16, R.uint16 }
FILTER_TYPE = R.tuple{ R.array2d( DXDY_TYPE, TILES_X*4, TILES_Y*4 ), POS_TYPE }

out = R.connect{ input = harrisOut, toModule =
  R.RV(R.modules.filterSeq{ type=FILTER_TYPE, size={W,H}, rate=FILTER_RATE, fifoSize=FILTER_FIFO }) }

out = R.fifo{ input = out, depth = 512, fifoList = fifoList }

-----------------------------------
-- fan out filterSeq result to store position along a side branch
branch0, branch1 = R.fanOut{ input = out, branches = 2 }

-----------------------------------
-- branch 0: hold pixel position of feature until we need it later
--local inp_pos = C.fifo( fifos, statements, FILTER_TYPE, branch0, 1, "p0", true) -- fifo size can also be 1 (tested in SW)
pos = R.index{ input = branch0, key = 1 }
pos = R.fifo{ input = pos, depth = 1024, fifoList = fifoList }

-----------------------------------
-- branch 1: calculate feature descriptor
--local inp_dxdy = C.fifo( fifos, statements, FILTER_TYPE, branch1, 1, "p1", true) -- fifo size can also be 1 (tested in SW)
dxdy = R.index{ input = branch1, key = 0 }

-- rearrange 16x16 stencil into 16 4x4 tiles
dxdyTile = R.connect{ input = dxdy, toModule = 
  R.RV( descriptor.tile(TILES_X*4,TILES_Y*4,4,DXDY_TYPE) ) }

-- Devectorize tile array
dxdy = R.connect{ input = dxdyTile, toModule = 
  R.RV( R.modules.changeRate{ type = R.array(DXDY_TYPE,16), H=1, inputW=TILES_X*TILES_Y, outputW=1}) }

-- Devectorize tile into pixels
dxdy = R.connect{ input = dxdy, toModule = 
  R.RV( R.modules.changeRate{ type=DXDY_TYPE, H=1,inputW=16, outputW=1} ) }

-- Assign each pixel in tile to correct histogram bucket (int8->int32[8])
desc = R.connect{ input = dxdy, toModule = R.RV( descriptor.descriptor ) }

-- Reduce histogram buckets (int32[8]->int32[8])
desc = R.connect{ input = desc, toModule = 
  R.RV( R.modules.reduceSeq{ fn = descriptor.histogramReduce, P=1/16}) }

desc = R.fifo{ input = desc, depth = 128, fifoList = fifoList }

-- Devectorize 8 histogram buckets into individual values to sum them
desc = R.connect{ input = desc, toModule = 
  R.RV( R.modules.changeRate{ type=R.int32, H=1, inputW=8, outputW=1 } ) }

-----------------------------------
-- fan out to sum and normalize the descriptors
branch2, branch3 = R.fanOut{ input = desc, branches = 2 }

-----------------------------------
-- branch 2: sum of squares
branch2 = R.fifo{ input = branch2, depth = 256, fifoList = fifoList }

desc_sum = R.connect{ input = branch2, toModule = 
  R.RV( R.modules.reduceSeq{ fn=
    R.modules.sumPow2{inputType=R.int32,outputType=R.int32}, P=1/(TILES_X*TILES_Y*8)} ) }

desc_sum = R.connect{ input = desc_sum, toModule = 
  R.RV(R.modules.sqrt{ inputType = R.int32, outputType = R.float }) }

-- duplicate
desc_sum = R.connect{ input = desc_sum, toModule = 
  R.modules.upsampleSeq{ type = R.float, P=1, size={W,H}, scale={TILES_X*TILES_Y*8,1} } }

-----------------------------------
-- branch 3: Normalize the descriptor values (depends on branch 2)
branch3 = R.fifo{ input = branch3, depth = 256, fifoList = fifoList }
branch3 = R.connect{ input = R.fanIn{branch3,desc_sum}, toModule = descriptor.normalize }
desc = R.connect{ input = branch3, toModule = 
  R.RV( R.modules.changeRate{ type = R.float, H=1, inputW=1, outputW=TILES_X*TILES_Y*8}) }

-----------------------------------
-- merge branch 2 and 3
desc = R.connect{ input = R.fanIn{desc,pos}, toModule = descriptor.addPos() }

-----------------------

descriptorPipeline = R.pipeline{ input = inp, output = desc, fifoList = fifoList }

R.harness{ fn = descriptorPipeline, 
            inputFile = "boxanim_256.raw", inputSize = {W,H},
            outputFile = "featuredescriptor", outputSize = {W*H*FILTER_RATE*130, 1} }
            