local R = require "rigel"
local RM = require "generators.modules"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"
local C = require "generators.examplescommon"
local RS = require "rigelSimple"
local f = require "fixed_new"
local G = require "generators.core"

W = 128
H = 64
size = {W,H}

pad={8,8}
padSize = {W+pad[1],H+pad[2]}

------------
inp = R.input( types.rv(types.Par(types.uint(8))) )
local posSeqMod = RS.modules.posSeq{size=padSize,V=1}
pos = RS.connect{toModule=posSeqMod,input=G.ValueToTrigger(inp)}

local pbinp = f.parameter("pbinp",posSeqMod.outputType.over.over):index(0)
local pbx = pbinp:index(0):mod(8):eq(f.constant(7))
local pby = pbinp:index(1):mod(8):eq(f.constant(7))
local pb = pbx:__and(pby)

posbool = RS.connect{ input=pos, toModule=pb:toRigelModule("pb") }
local pout = RS.connect{ input=RS.concat{posbool,inp,RS.constant{value=0,type=RS.uint8} }, toModule = C.select(RS.uint8) }
sparseInput = RM.lambda( "sparseInput", inp, pout )
--print(sparseInput)
------------
inp = R.input( types.rv(types.Par(RS.array2d(RS.uint8,1))) )
out = RS.index{input=inp,key=0}
out = RS.connect{input=out, toModule=sparseInput}
--out = RS.connect{input=out, toModule=RM.sparseLinebuffer(RS.uint8,W,H,32,-2,0) }
out = C.broadcast(RS.uint8,1,1)(out)
out = RS.connect{input=out, toModule=RM.linebuffer(RS.uint8,W+pad[1],H+pad[2],1,-2) }
out = RS.connect{input=out, toModule=RM.SSR(RS.uint8,1,-2,-2)}
out = RS.connect{input=out, toModule=C.convolveConstant(RS.uint8, 3,3,{1,1,1,1,1,1,1,1,1},0) }
out = RS.connect{input=out, toModule=C.arrayop(RS.uint8,1,1) }
fn = RM.lambda( "pointwise_wide", inp, out )
------------
hsfn = RM.makeHandshake(fn)

--hsfn = C.compose("hsfnc", RS.HS(RS.modules.cropSeq{type=RS.uint8,size=size,crop={2,0,2,0},V=1}),hsfn )
hsfn = C.linearPipeline{ RS.HS(RS.modules.padSeq{type=RS.uint8,size=size,pad={pad[1],0,pad[2],0},value=0,V=1}),
			 hsfn,
			 RS.HS(RS.modules.cropSeq{type=RS.uint8,size=padSize,crop={pad[1],0,pad[2],0},V=1}) }

harness{ outFile="sparselb_dense", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H} }
