local R = require "rigel"
local RM = require "modules"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"
local RS = require "rigelSimple"
local f = require "fixed_new"

W = 128
H = 64
size = {W,H}

pad={8,8}
padSize = {W+pad[1],H+pad[2]}

------------
inp = R.input( types.uint(8) )
local posSeqMod = RS.modules.posSeq{size=padSize,V=1}
pos = RS.connect{toModule=posSeqMod}

local pbinp = f.parameter("pbinp",posSeqMod.outputType):index(0)
local pbx = pbinp:index(0):mod(8):eq(f.constant(7))
local pby = pbinp:index(1):mod(8):eq(f.constant(7))
local pb = pbx:__and(pby)

posbool = RS.connect{ input=pos,toModule=pb:toRigelModule("pb") }
sparseInput = RM.lambda( "sparseInput", inp, RS.concat{ inp, posbool } )

------------
inp = R.input( RS.array2d(RS.uint8,1) )
out = RS.index{input=inp,key=0}
out = RS.connect{input=out, toModule=sparseInput}
out = RS.connect{input=out, toModule=RM.sparseLinebuffer(RS.uint8,W+pad[1],H+pad[2],32,-2,0) }
out = RS.connect{input=out, toModule=RM.SSR(RS.uint8,1,-2,-2)}
out = RS.connect{input=out, toModule=C.convolveConstant(RS.uint8, 3,3,{1,1,1,1,1,1,1,1,1},0) }
out = RS.connect{input=out, toModule=C.arrayop(RS.uint8,1,1) }
fn = RM.lambda( "pointwise_wide", inp, out )
------------
hsfn = RM.makeHandshake(fn)

--hsfn = C.compose("hsfnc", 
hsfn = C.linearPipeline{ RS.HS(RS.modules.padSeq{type=RS.uint8,size=size,pad={pad[1],0,pad[2],0},value=0,V=1}),
			 hsfn,
			 RS.HS(RS.modules.cropSeq{type=RS.uint8,size=padSize,crop={pad[1],0,pad[2],0},V=1}) }

harness{ outFile="sparselb", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H} }
