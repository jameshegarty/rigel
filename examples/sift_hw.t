local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"

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
    print("OUTPUTBYTES",outputBytes,"PADBYTES",padAmount)
    padAmount = padAmount / 4

    ------------
    -- pad out to axi burst size
    local inp = d.input(d.Handshake(ITYPE))
    local out = d.apply("SFT",siftFn,inp)
    local out = d.apply("PS",d.liftHandshake(d.padSeq(siftType,outputCount,1,2,0,padAmount,0,0,0)),out)
    hsfn = d.lambda("sdf",inp,out)
    ---------

    outputCount = outputCount+padAmount
  else
    hsfn = siftFn
  end

  harness.axi( "sift_hw"..sel(full,"_1080p",""), hsfn, sel(full,"boxanim0000.raw","box_256.raw"), nil, nil, ITYPE, 8, W, H, OTYPE, 2, outputCount,1)

end

doit(string.find(arg[0],"1080p")~=nil)