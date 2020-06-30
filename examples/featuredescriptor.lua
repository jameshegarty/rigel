local rigel = require "rigel"
rigel.AUTO_FIFOS = false

local R = require "rigelSimple"
local harris = require "harris_core"
local descriptor = require "descriptor_core"
local G = require "generators.core"
local C = require "generators.examplescommon"
local types = require "types"

W, H = 256, 256
TILES_X, TILES_Y = 4, 4
OUTPUT_COUNT = 614
FILTER_RATE, FILTER_FIFO = {OUTPUT_COUNT,W*H}, 512
--fifoList = {}

-----------------------------------
-- Start of pipeline: apply harris
inp = R.input(R.HS(R.array(R.uint8,1)))
harrisOut = R.connect{ input = inp, toModule = harris.harrisWithStencil{W=W,H=H} }
  
-----------------------------------
-- filterSeq
DXDY_TYPE = R.tuple{ R.int8, R.int8 }
POS_TYPE = R.tuple{ R.uint16, R.uint16 }
FILTER_TYPE = R.tuple{ R.array2d( DXDY_TYPE, TILES_X*4, TILES_Y*4 ), POS_TYPE }

filterSeqOut = R.connect{ input = harrisOut, toModule = R.HS(R.modules.filterSeq{ 
  type=FILTER_TYPE, size={W,H}, rate=FILTER_RATE, fifoSize=FILTER_FIFO, coerce=false }) }

--filterSeqOut = R.fifoLoop{ input = filterSeqOut, depth = 512, fifoList = fifoList }
filterSeqOut = G.FIFO{512}(filterSeqOut)

-----------------------------------
-- fan out filterSeq result to store position along a side branch
branch0, branch1 = R.fanOut{ input = filterSeqOut, branches = 2 }

-----------------------------------
-- branch 0: hold pixel position of feature until we need it later
branch0_pos = R.index{ input = branch0, key = 1 }
--branch0_pos = R.fifoLoop{ input = branch0_pos, depth = 1024, fifoList = fifoList }
branch0_pos = G.FIFO{1024}(branch0_pos)

-----------------------------------
-- branch 1: calculate feature descriptor
branch1 = R.index{ input = branch1, key = 0 }

-- rearrange 16x16 stencil into 16 4x4 tiles
branch1_tiles = R.connect{ input = branch1, toModule = 
  R.HS( descriptor.tile(TILES_X*4,TILES_Y*4,4,DXDY_TYPE) ) }

-- Devectorize tile array
branch1_tile = R.connect{ input=branch1_tiles, toModule=R.HS( R.modules.devectorize{ 
  type=R.array(DXDY_TYPE,16), V=TILES_X*TILES_Y}) }

-- Devectorize tile into pixels
branch1_pixels = R.connect{ input = branch1_tile, toModule = 
  R.HS( R.modules.devectorize{ type=DXDY_TYPE, V=16} ) }

-- Assign each pixel in tile to correct histogram bucket (int8->int32[8])
branch1_desc = R.connect{ input=branch1_pixels, toModule=R.HS(descriptor.descriptor)}

-- Reduce histogram buckets (int32[8]->int32[8])
branch1_hist = R.connect{ input = branch1_desc, toModule = 
  R.HS( R.modules.reduceSeq{ fn = descriptor.histogramReduce, V=16}) }

--branch1_hist = R.fifoLoop{ input = branch1_hist, depth = 128, fifoList = fifoList }
branch1_hist = G.FIFO{128}(branch1_hist)

-- Devectorize 8 histogram buckets into individual values to sum them
branch1_histbucket = R.connect{ input = branch1_hist, toModule = 
  R.HS( R.modules.devectorize{ type=R.int32, V=8 } ) }

-----------------------------------
-- fan out to sum and normalize the descriptors
branch2, branch3 = R.fanOut{ input = branch1_histbucket, branches = 2 }

-----------------------------------
-- branch 2: sum of squares
--branch2 = R.fifoLoop{ input = branch2, depth = 256, fifoList = fifoList }
branch2 = G.FIFO{256}(branch2)

-- sum all 128 histogram buckets
branch2 = G.Map{G.ItoFR}(branch2)
branch2 = G.Map{G.Pow2}(branch2)
branch2 = G.DeserSeq{TILES_X*TILES_Y*8}(branch2)
branch2 = G.Reduce{G.AddF}(branch2)

-- calculate sqrt of sum
branch2 = G.SqrtF( branch2 )
local branch2_sumsqrt = G.Float(branch2)

-- duplicate the sum 128 times to normalize each 128 histogram bucket
branch2_sum = R.connect{ input = branch2_sumsqrt, toModule = 
  R.modules.upsampleSeq{type=R.float, V=1, size={W,H}, scale={TILES_X*TILES_Y*8,1}}}

-----------------------------------
-- branch 3: Normalize the descriptor values (depends on branch 2)
--branch3 = R.fifoLoop{ input = branch3, depth = 256, fifoList = fifoList }
branch3 = G.FIFO{256}(branch3)

-- divide each 128 histogram bucket value by the sum of the buckets
branch3 = R.connect{input=R.fanIn{branch3,branch2_sum},toModule=descriptor.normalize}

-- convert stream of histogram buckets back into 128 element normalize descriptor
branch3_descnorm = R.connect{ input = branch3, toModule = 
  R.HS( R.modules.vectorize{ type = R.float, V=TILES_X*TILES_Y*8}) }

-----------------------------------
-- merge branch 2 and 3
desc = R.connect{ input = R.fanIn{branch3_descnorm,branch0_pos}, toModule = 
  descriptor.addPos() }

desc = G.Bitcast{types.array2d(types.uint(8),130*4)}(desc)

-----------------------
descriptorPipeline = R.defineModule{ input=inp, output=desc }

R.harness{ fn = descriptorPipeline, 
            inFile = "boxanim_256.raw", inSize = {W,H},
            outFile = "featuredescriptor", outSize = {130*4, OUTPUT_COUNT}, outP=130*4 }
            
