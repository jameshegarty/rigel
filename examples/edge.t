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
--local THRESH = 10
local THRESH = 7
local inp = S.parameter("inp",types.uint(8))
local c_one = S.constant({255,255,255,0},types.array2d(types.uint(8),4))
local c_zero = S.constant({0,0,0,0},types.array2d(types.uint(8),4))
local thout = S.select(S.gt(inp,S.constant(THRESH,types.uint(8))), c_one, c_zero )
local thfn = RM.lift("thfn", ty,types.array2d(types.uint(8),4),10,terra(a:&uint8,out:&uint8[4])
                      if @a > THRESH then 
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
thfn = RM.makeHandshake(RM.map(thfn,T))

--------------

local BW = (TConvWidth-1)/2
local blurfn = C.stencilKernelPadcrop( types.uint(8), W,H,T,BW,BW,BW,BW,0,convolvefn,false)
local edgefn = C.stencilKernelPadcrop( types.uint(8), W,H,T,1,1,1,1,0,edge,false)
local nmsfn = C.stencilKernelPadcrop( types.uint(8), W,H,T,1,1,1,1,0,nms,false)

local inp = R.input(R.Handshake(ITYPE))
local out = inp
local out = R.apply("incrate", RM.liftHandshake(RM.changeRate(types.uint(8),1,8,2)), out )
local out = R.apply("bf",blurfn,out)
--local out = R.apply("ds",C.downsampleSeq(types.uint(8),W,H,T,2,2),out)
local out = R.apply("ef",edgefn,out)
--local out = R.apply("bff",blurfn,out)
--local out = R.apply("nf",nmsfn,out)
local out = R.apply("nf",thfn,out)
--local out = R.apply("us",C.upsampleSeq(types.uint(8),W/2,H/2,T,2,2),out)
local hsfn = RM.lambda("hsfn",inp,out)
--local hsfn = C.compose("hsfn",blurfn,edgefn)

--hsfn = RM.makeHandshake(fn)

harness.axi( "edge", hsfn, "ov7660_1chan.raw", nil, nil, ITYPE, 8,W,H, OTYPE,2,W,H)
