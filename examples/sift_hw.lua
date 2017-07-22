local R = require "rigel"
local RM = require "modules"
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local J = require "common"

GRAD_INT = true
GRAD_SCALE = 4 -- <2 is bad
GRAD_TYPE = types.int(8)

local sift = require "sift_core_hw"

function doit(full)
  local W = 256
  local H = 256

  if full then W,H = 1920,1080 end

  local T = 8

  local FILTER_FIFO = 512
  local FILTER_RATE = 128

  local ITYPE = types.array2d(types.uint(8),T)
  local siftFn, siftType = sift.siftTop(W,H,T,FILTER_RATE,FILTER_FIFO)
  local OTYPE = types.array2d(siftType,2)

  local outputCount = ((W*H)/FILTER_RATE)*130
  local outputBytes = outputCount*4
  local hsfn

  if outputBytes/128 ~= math.floor(outputBytes/128) then

    local padAmount = 128-(outputBytes%128)
    padAmount = padAmount / 4

    ------------
    -- pad out to axi burst size
    local inp = R.input(R.Handshake(ITYPE))
    local out = R.apply("SFT",siftFn,inp)
    local out = R.apply("PS",RM.liftHandshake(RM.padSeq(siftType,outputCount,1,2,0,padAmount,0,0,0)),out)
    hsfn = RM.lambda("sdf",inp,out)
    ---------

    outputCount = outputCount+padAmount
  else
    hsfn = siftFn
  end

  harness{ outFile="sift_hw"..J.sel(full,"_1080p",""), fn=hsfn, inFile=J.sel(full,"boxanim0000.raw","boxanim_256.raw"), inSize={W,H}, outSize={outputCount,1} }

end

doit(string.find(arg[0],"1080p")~=nil)
