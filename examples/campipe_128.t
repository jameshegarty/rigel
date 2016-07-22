local R = require "rigel"
local RM = require "modules"
local CC = require "campipe_core"

function makeCampipeTop()
  -- inp -> |blacklevel| -> |Demosaic| -> |CCM| -> |Gamma| -> out
  local input = rigelInput(grayscale_uint8)
  local bl_out = connect{input=input, tomodule=BlackLevel}
  local dem_out = connect{input=bl_out, tomodule=Demosaic}
  local ccm_out = connect{input=dem_out, tomodule=CCM}
  local gamma_out = connect{input=ccm_out, tomodule=Gamma}
  return rigelPipeline{input=input, output=gamma_out}
end


local types = require("types")
local harness = require "harness"
local f = require "fixed"
local modules = require "fpgamodules"
local C = require "examplescommon"

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


local ITYPE = types.array2d(types.uint(8),T)

local X1 = false
if string.find(arg[0],"1x") then X1=true end

if string.find(arg[0],"128") then
  W,H = 128,128
  inputFilename = "300d_w"..W.."_h"..H..".raw"
  outputFilename = "campipe_"..W
--  phaseX, phaseY = 1,0
elseif string.find(arg[0],"ov7660") then
  W,H=640,480

  T = 4
  if X1 then T=8 end
  if X1==false then ITYPE = types.array2d(types.array2d(types.uint(8),2),T) end

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

  inputFilename = "ov7660.raw"
  if X1 then inputFilename = "ov7660_1chan.raw" end

  outputFilename = "campipe_ov7660"
  if X1 then   outputFilename = "campipe_ov7660_1x" end
  pedestal = 90
  gamma = 1.2
ccmtab={ {255/176,0,0},
{0, 289/255, 0},
{0,0,255/176}}

--  phaseX, phaseY = 0,0
end

----------------
local rgbType = types.array2d(types.uint(8),4)
local OTYPE = types.array2d(rgbType,2)

BlackLevel={}
Demosaic={}
CCM={}
Gamma={}

function makeCampipe(internalW,internalH)
  print("makeCampipe",internalW,internalH)
  assert(type(internalH)=="number")
  local internalT = 2

--  local inp = R.input(types.array2d(types.uint(8),internalT))
--  local bl = R.apply("bl",RM.map(CC.blackLevel(pedestal),internalT),inp)
  BlackLevel = RM.map(CC.blackLevel(pedestal),internalT)
--  local dem = R.apply("dem",CC.demosaic(internalW,internalH,internalT,DEMOSAIC_W,DEMOSAIC_H,DEMOSAIC_R,DEMOSAIC_G,DEMOSAIC_B),bl)
  Demosaic = CC.demosaic(internalW,internalH,internalT,DEMOSAIC_W,DEMOSAIC_H,DEMOSAIC_R,DEMOSAIC_G,DEMOSAIC_B)
--  local ccm = R.apply("ccm",RM.map(CC.makeCCM(ccmtab),internalT),dem)
  CCM = RM.map(CC.makeCCM(ccmtab),internalT)
--  local gam = R.apply("gam",RM.map(RM.map(RM.lut(types.uint(8),types.uint(8),CC.makeGamma(1/gamma)),3),internalT),ccm)
  Gamma = RM.map(RM.map(RM.lut(types.uint(8),types.uint(8),CC.makeGamma(1/gamma)),3),internalT)
  --local out = R.apply("addchan",RM.map(CC.addchan(),internalT),gam)

  --local campipe = RM.lambda("campipe",inp,out)

  --return RM.makeHandshake(campipe)
  local cp = makeCampipeTop()
  return RM.makeHandshake(C.compose("ccomp",RM.map(CC.addchan(),internalT),cp))
--  return RM.makeHandshake(cp)
end

local STR_W = (DEMOSAIC_W-1)/2
local STR_H = (DEMOSAIC_H-1)/2
local campipe = C.padcrop(types.uint(8),W,H,2,STR_W,STR_W,STR_H,STR_H,0,makeCampipe)

local hsfninp = R.input(R.Handshake(ITYPE))

local hsfnout = hsfninp

local hsfnout = R.apply("incrate", RM.liftHandshake(RM.changeRate(ITYPE:arrayOver(),1,T,2)), hsfnout )

if string.find(arg[0],"ov7660") and X1==false then
  -- for the camera board setup, expect 2 cameras
  hsfnout = R.apply("idx",RM.makeHandshake(RM.map(C.index(types.array2d(types.uint(8),2),0),2)), hsfnout)
end

local hsfnout = R.apply("O1",campipe,hsfnout)

local hsfn = RM.lambda("hsfn",hsfninp,hsfnout)

harness.axi( outputFilename, hsfn, inputFilename, nil, nil, ITYPE, T,W,H, OTYPE,2,W,H)
