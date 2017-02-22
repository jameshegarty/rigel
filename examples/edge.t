local R = require "rigel"
local RM = require "modules"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"
local C = require "examplescommon"
local f = require "fixed"

W = 640
H = 480
T = 2

ITYPE = types.array2d( types.uint(8), 8 )
OTYPE = types.array2d( types.array2d(types.uint(8),4), 2 )
local TTYPE = types.array2d( types.uint(32), 4 ):makeConst()

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
local edge = mag:toDarkroom("edgefn")
--------------
-- nms
local ty = types.uint(8)
local inp = S.parameter("inp",types.array2d(types.uint(8),3,3))
local nms_N = S.gt(S.index(inp,1,1),S.index(inp,1,0))
local nms_S = S.ge(S.index(inp,1,1),S.index(inp,1,2))
local nms_E = S.gt(S.index(inp,1,1),S.index(inp,2,1))
local nms_W = S.ge(S.index(inp,1,1),S.index(inp,0,1))
local nmsout = S.__and(S.__and(nms_N,nms_S),S.__and(nms_E,nms_W))
local nmsout = S.select(nmsout, S.constant(255,types.uint(8)), S.constant(0,types.uint(8)) )
local nms = RM.lift("nms", types.array2d(ty,3,3),ty,10,terra(a:&uint8[9],out:&uint8)
                      var N = (@a)[1+1*3] >= (@a)[1+0*3]
                      var So = (@a)[1+1*3] >= (@a)[1+2*3]
                      var E = (@a)[1+1*3] >= (@a)[2+1*3]
                      var W = (@a)[1+1*3] >= (@a)[0+1*3]
                      var nmsout = (N and So) or (E and W)
                      nmsout = nmsout and ( (@a)[1+1*3] > 10 )

--                      nmsout = (@a)[1+1*3] > 10
                      if nmsout then @out=255 else @out = 0 end
                                    end, inp, nmsout)

--------------
local function makeThresh()
--  local THRESH = 10
  local inptype = types.tuple{types.uint(8),types.uint(32):makeConst()}
  local inp = S.parameter( "inp", inptype )
  local inpData = S.index( inp, 0 )
  local inpTap = S.index( inp, 1 )
  local c_one = S.constant({255,255,255,0},types.array2d(types.uint(8),4))
  local c_zero = S.constant({0,0,0,0},types.array2d(types.uint(8),4))
  local thout = S.select(S.gt(inpData,inpTap), c_one, c_zero )
  local thfn = RM.lift("thfn", inptype, types.array2d(types.uint(8),4),10,terra(a:&tuple(uint8,uint32),out:&uint8[4])
                         if (@a)._0 > (@a)._1 then 
                           (@out)[0]=255 
                           (@out)[1]=255 
                           (@out)[2]=255 
                           (@out)[3]=0
                         else 
                           (@out)[0] = 0 
                           (@out)[1] = 0 
                           (@out)[2] = 0 
                           (@out)[3] = 0 
                         end
                                                                    end, inp, thout)

  if TAPS==false then
    local THRESH=10
    local inp = R.input( types.uint(8) )
    local out = R.apply("rr", thfn, R.tuple("rof",{inp,R.constant("Rt",THRESH,types.uint(32):makeConst())}))
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
if TAPS then
  FNTYPE = types.tuple{ITYPE,TTYPE}
else
  FNTYPE = ITYPE
end

local inp = R.input(R.Handshake(FNTYPE))
local out
local inptaps

if TAPS then
  out = R.apply( "i0", RM.makeHandshake(C.index(FNTYPE,0)), inp)
  inptaps = R.apply("idx1",RM.makeHandshake(C.index(FNTYPE,1)), inp)
  inptaps = R.apply("idx11",RM.makeHandshake(C.index(TTYPE,0)), inptaps)
  inptaps = R.apply("IIT", RM.makeHandshake(C.broadcast(types.uint(32):makeConst(),2)), inptaps)
else
  out = inp
--  inptaps = R.constant( "idx1", 10, types.uint(32) )
--  inptaps = R.apply("IIT", C.broadcast(types.uint(32),2), inptaps)
end

local out = R.apply("incrate", RM.liftHandshake(RM.changeRate(types.uint(8),1,8,2)), out )
local out = R.apply("bf",blurfn,out)
local out = R.apply("ef",edgefn,out)

if TAPS then
  out = R.apply("oack",C.SoAtoAoSHandshake(2,1,{types.uint(8),types.uint(32):makeConst()}),R.tuple("RT",{out,inptaps},false))
end

local out = R.apply("nf",thfn,out)

local hsfn = RM.lambda("hsfn",inp,out)

if TAPS then
  harness{ outFile="edge_taps", fn=hsfn, inFile="ov7660_1chan.raw", tapType=TTYPE, tapValue={10,0,0,0}, inSize={W,H}, outSize={W,H} }
else
  harness{ outFile="edge", fn=hsfn, inFile="ov7660_1chan.raw", inSize={W,H}, outSize={W,H} }
end
