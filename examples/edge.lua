local R = require "rigel"
local RM = require "generators.modules"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
--local cstdio = terralib.includec("stdio.h")
--local cstring = terralib.includec("string.h")
local harness = require "generators.harness"
local C = require "generators.examplescommon"
local f = require "fixed"
local soc = require "generators.soc"


local edgeTerra={}
if terralib~=nil then edgeTerra=require("edge_terra") end

W = 640
H = 480
T = 2

ITYPE = types.array2d( types.uint(8), 8 )
OTYPE = types.array2d( types.array2d(types.uint(8),4), 2 )
--local TTYPE = types.array2d( types.uint(32), 4 ):makeConst()
local TTYPE = types.uint(32)
local TAPVALUE =10
--soc.taps = R.newGlobal("taps","input",TTYPE,TAPVALUE)
local taps = soc.regStub{taps={TTYPE,TAPVALUE}}:instantiate("taps")
taps.extern = true

TAPS = false

if string.find(arg[0],"taps") then TAPS=true end

--------------
-- blur kernel
TConvWidth = 3
local gauss = C.gaussian(TConvWidth,3)
local convolvefn = C.convolveConstant( types.uint(8), TConvWidth, TConvWidth, gauss, 6 )
--------------
-- edge
local ty = types.uint(8)
local inp = f.parameter("nmsinp", types.array2d(ty,3,3))
local dx = inp:index(2,1):lift(0):toSigned()-inp:index(0,1):lift(0):toSigned()
dx = dx:abs()
local dy = inp:index(1,2):lift(0):toSigned()-inp:index(1,0):lift(0):toSigned()
dy = dy:abs()
local mag = (dx+dy):truncate(8):lower()
local edge = mag:toRigelModule("edgefn")
--------------
-- nms
local ty = types.uint(8)

local nms = RM.lift("nms", types.array2d(ty,3,3),ty,10,
  function(inp)
    local nms_N = S.gt(S.index(inp,1,1),S.index(inp,1,0))
    local nms_S = S.ge(S.index(inp,1,1),S.index(inp,1,2))
    local nms_E = S.gt(S.index(inp,1,1),S.index(inp,2,1))
    local nms_W = S.ge(S.index(inp,1,1),S.index(inp,0,1))
    local nmsout = S.__and(S.__and(nms_N,nms_S),S.__and(nms_E,nms_W))
    return S.select(nmsout, S.constant(255,types.uint(8)), S.constant(0,types.uint(8)) )
  end,
  function() return edgeTerra.nms end)

--------------
local function makeThresh()
  local inptype = types.tuple{types.uint(8),types.uint(32)}

  local thfn = RM.lift("thfn", inptype, types.array2d(types.uint(8),4),0,
    function(inp)
      local inpData = S.index( inp, 0 )
      local inpTap = S.index( inp, 1 )
      local c_one = S.constant({255,255,255,0},types.array2d(types.uint(8),4))
      local c_zero = S.constant({0,0,0,0},types.array2d(types.uint(8),4))
      return S.select(S.gt(inpData,inpTap), c_one, c_zero )
    end,
   function() return edgeTerra.thresh end)

  if TAPS==false then
    local THRESH=10
    local inp = R.input( types.rv(types.Par(types.uint(8))) )
    local out = R.apply("rr", thfn, R.concat("rof",{inp,R.constant("Rt",THRESH,types.uint(32))}))
    thfn = RM.lambda("EWR",inp,out)
  end

  return RM.makeHandshake(RM.map(thfn,T))
end

local thfn = makeThresh()

--------------

local BW = (TConvWidth-1)/2
local blurfn = C.stencilKernelPadcrop( types.uint(8), W,H,T,BW,BW,BW,BW,0,convolvefn,false)
local edgefn = C.stencilKernelPadcrop( types.uint(8), W,H,T,1,1,1,1,0,edge,false)
local nmsfn = C.stencilKernelPadcrop( types.uint(8), W,H,T,1,1,1,1,0,nms,false)

local FNTYPE
FNTYPE = ITYPE

local inp = R.input(R.Handshake(FNTYPE))

local out
local inptaps

out = inp

local out = R.apply("incrate", RM.liftHandshake(RM.changeRate(types.uint(8),1,8,2)), out )
local out = R.apply("bf",blurfn,out)
local out = R.apply("ef",edgefn,out)

if TAPS then
  out = R.apply("oack",RM.makeHandshake(C.packTapBroad(types.array2d(types.uint(8),T),TTYPE,taps.taps,T)),out)
  out = R.apply("SOS",RM.makeHandshake(RM.SoAtoAoS(2,1,{types.uint(8),TTYPE})),out)
end

local out = R.apply("nf",thfn,out)

local hsfn = RM.lambda("hsfn",inp,out)

if TAPS then
  harness{ outFile="edge_taps", fn=hsfn, inFile="ov7660_1chan.raw", tapType=TTYPE, tapValue=TAPVALUE, inSize={W,H}, outSize={W,H} }
else
  harness{ outFile="edge", fn=hsfn, inFile="ov7660_1chan.raw", inSize={W,H}, outSize={W,H} }
end
