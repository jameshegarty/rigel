local types = require("types")

GRAD_INT = true
GRAD_SCALE = 4 -- <2 is bad
GRAD_TYPE = types.int(8)

local sift = require("sift_core_hw")
local rigel = require "rigel"
local R = require "rigelSimple"
local RM = require "modules"
local C = require "examplescommon"

local descriptor = {}

function descriptor.addPos()
  local descType = types.float(32)
  local PTYPE = R.tuple{types.array2d(descType,TILES_X*TILES_Y*8),R.tuple{R.uint16,R.uint16}}
  local POS_TYPE = R.tuple{R.uint16,R.uint16}

  local inp = R.input(PTYPE)
  local desc = rigel.apply("pxd",C.index(PTYPE,0),inp)
  local pos = rigel.apply("p",C.index(PTYPE,1),inp)
  local posx = rigel.apply("px",C.index(POS_TYPE,0),pos)
  local posy = rigel.apply("py",C.index(POS_TYPE,1),pos)
  local repack = R.defineModule{input=inp,output = R.concat{desc,posx,posy} }


--------------------------

  local inp = rigel.input( R.HS(PTYPE) )

  local desc_pack = R.connect{ input = inp, toModule = R.HS(repack) }
  local desc = rigel.apply("addpos",RM.makeHandshake(sift.addDescriptorPos(descType)), desc_pack)

  return R.defineModule{ input = inp, output = desc }
end

descriptor.tile = sift.tile

descriptor.histogramReduce = sift.bucketReduce(types.int(32), 8 )
descriptor.descriptor = sift.siftDescriptor(types.int(8))

function norm()
  local inp = R.input( R.HS( R.tuple{ R.array(R.int32,1), R.array(R.float,1) } ) )
  local inp0, inp1 = R.fanOut{input=inp, branches=2}

  local desc_sum = R.index{input=R.index{input=inp0, key=1 }, key=0}
  local desc0 = rigel.apply("d0lift",RM.makeHandshake(sift.fixedLift(R.int32)), R.index{input=R.index{input=inp1,key=0 },key=0} )
  
  local desc = rigel.apply("pt",RM.packTuple({R.float,R.float},true),rigel.concat("PTT",{desc0,desc_sum}))
  local desc = rigel.apply("ptt",RM.makeHandshake(sift.fixedDiv(R.float)),desc)
  return R.defineModule{input=inp,output=desc}
end

descriptor.normalize = norm()

return descriptor
