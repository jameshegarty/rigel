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
T = 8

ITYPE = types.uint(8)

inp = R.input( RS.HS(ITYPE) )

local inpb = G.FanOut{2}(inp)
local inp0 = G.FIFO{128}(inpb[0])
local inp1 = G.FIFO{128}(inpb[1])

posseq = RS.connect{ toModule=RS.HS(RM.posSeq(W,H,1),false), name="posseqinst", input=G.ValueToTrigger(inp0) }

local mergeinp = f.parameter( "inp", types.tuple{ITYPE,types.tuple{types.uint(16),types.uint(16)} } )
mergefn = (mergeinp:index(0):rshift(4):removeLSBs(4):addMSBs(12)+mergeinp:index(1):index(0))+mergeinp:index(1):index(1):addMSBs(1)
mergefn = mergefn:removeMSBs(10)
  
merge = RS.connect{ input=RS.fanIn{inp1,RS.index{input=posseq,key=0}}, toModule=RS.HS(mergefn:toRigelModule("mergefn")), name="merge" }
                     
fn = RM.lambda( "pointwise_wide", inp, merge )
------------
--hsfn = RM.makeHandshake(fn)

harness{ outFile="nilhandshake", fn=fn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H} }
