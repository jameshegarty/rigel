local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"
local f = require "fixed"
local modules = require "fpgamodules"
local C = require "examplescommon"
local CC = require "campipe_core"

W = 512
H = 512

T = 8
phaseX=1
phaseY=1

local inputFilename = "300d_w"..W.."_h"..H..".raw"
local outputFilename = "campipe_"..W

local pedestal = 10

ccmtab={ {255/142,0,0},
{0, 196/255, 0},
{0,0,1}}

gamma = 2.4

local r_tl = {1,0,1,
              0,0,0,
              1,0,1}
local r_tr = {0,2,0,
              0,0,0,
              0,2,0}
local r_bl = {0,0,0,
              2,0,2,
              0,0,0}
local r_br = {0,0,0,
              0,4,0,
              0,0,0}
DEMOSAIC_R = {r_bl,r_br,r_tl,r_tr}

local g_tl = {0,1,0,
              1,0,1,
              0,1,0}
local g_tr = {0,0,0,
              0,4,0,
              0,0,0}
local g_bl = {0,0,0,
              0,4,0,
              0,0,0}
local g_br = {0,1,0,
              1,0,1,
              0,1,0}
DEMOSAIC_G = {g_bl,g_br,g_tl,g_tr}

local b_tl = {0,0,0,
              0,4,0,
              0,0,0}
local b_tr = {0,0,0,
              2,0,2,
              0,0,0}
local b_bl = {0,2,0,
              0,0,0,
              0,2,0}
local b_br = {1,0,1,
              0,0,0,
              1,0,1}
DEMOSAIC_B = {b_bl,b_br,b_tl,b_tr}

DEMOSAIC_W = 3
DEMOSAIC_H = 3


if string.find(arg[0],"128") then
  W,H = 128,128
  inputFilename = "300d_w"..W.."_h"..H..".raw"
  outputFilename = "campipe_"..W
--  phaseX, phaseY = 1,0
elseif string.find(arg[0],"ov7660") then
  W,H=640,480

  -- for some reason the two greens of the ov7660 don't line up. just ignore one
  local g_tl = {0,2,0,
                0,0,0,
                0,2,0}
  local g_tr = {1,0,1,
                0,0,0,
                1,0,1}
  local g_bl = {0,0,0,
                0,4,0,
                0,0,0}
  local g_br = {0,0,0,
                2,0,2,
                0,0,0}
  DEMOSAIC_G = {g_bl,g_br,g_tl,g_tr}

  DEMOSAIC_R = map(DEMOSAIC_R,CC.kernelPad)
  DEMOSAIC_R = map(DEMOSAIC_R, function(t) return CC.shiftKernel(t,7,3,2,0) end )
  DEMOSAIC_G = map(DEMOSAIC_G,CC.kernelPad)
  DEMOSAIC_B = map(DEMOSAIC_B,CC.kernelPad)

  DEMOSAIC_W = 7
  DEMOSAIC_H = 3

  inputFilename = "cam1_0.raw"
--  inputFilename = "outrgb.raw"
  outputFilename = "campipe_ov7660"
  pedestal = 90
  gamma = 1.2
ccmtab={ {255/176,0,0},
{0, 289/255, 0},
{0,0,255/176}}

--  phaseX, phaseY = 0,0
end

----------------
local ITYPE = types.array2d(types.uint(8),T)
local rgbType = types.array2d(types.uint(8),4)
local OTYPE = types.array2d(rgbType,2)

function makeCampipe(internalW,internalH)
  local inp = d.input(ITYPE)
  local bl = d.apply("bl",d.map(CC.blackLevel(pedestal),T),inp)
  local dem = d.apply("dem",CC.demosaic(internalW,internalH,DEMOSAIC_W,DEMOSAIC_H,DEMOSAIC_R,DEMOSAIC_G,DEMOSAIC_B),bl)
  local ccm = d.apply("ccm",d.map(CC.makeCCM(ccmtab),T),dem)
  local gam = d.apply("gam",d.map(d.map(d.lut(types.uint(8),types.uint(8),CC.makeGamma(1/gamma)),3),T),ccm)
  local out = d.apply("addchan",d.map(CC.addchan(),T),gam)
  --local dem = d.apply("fake",d.map(C.arrayop(types.uint(8),4),T),bl)
  local campipe = d.lambda("campipe",inp,out)
  
--  local hsfninp = d.input(d.Handshake(ITYPE))
--  local hsfnout = d.apply("O1",d.makeHandshake(campipe),hsfninp)
--  local hsfnout = d.apply("incrate", d.liftHandshake(d.changeRate(rgbType,1,T,2)), hsfnout )
--  local hsfn = d.lambda("hsfn",hsfninp,hsfnout)

  return d.makeHandshake(campipe)
end

local campipe = C.padcrop(types.uint(8),W,H,T,1,1,1,1,0,makeCampipe)
--print("HSFN",hsfn.outputType)
--hsfn = d.compose("hsfn",hsfn,d.liftHandshake(d.changeRate(rgbType,1,T,2)))

local hsfninp = d.input(d.Handshake(ITYPE))
local hsfnout = d.apply("O1",campipe,hsfninp)
local hsfnout = d.apply("incrate", d.liftHandshake(d.changeRate(rgbType,1,T,2)), hsfnout )
local hsfn = d.lambda("hsfnfin",hsfninp,hsfnout)

harness.axi( outputFilename, hsfn, inputFilename, nil, nil, ITYPE, T,W,H, OTYPE,2,W,H)
