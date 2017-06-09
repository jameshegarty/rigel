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
T = 8

ITYPE = types.uint(8)

inp = R.input( RS.HS(ITYPE) )

posseq = RS.connect{ toModule=RS.HS(RM.posSeq(W,H,1)), name="posseqinst" }

local mergeinp = f.parameter( "inp", types.tuple{ITYPE,types.tuple{types.uint(16),types.uint(16)} } )
mergefn = (mergeinp:index(0):rshift(4):removeLSBs(4):addMSBs(12)+mergeinp:index(1):index(0))+mergeinp:index(1):index(1):addMSBs(1)
mergefn = mergefn:removeMSBs(10)
  
merge = RS.connect{ input=RS.fanIn{inp,RS.index{input=posseq,key=0}}, toModule=RS.HS(mergefn:toRigelModule("mergefn")), name="merge" }
                     
fn = RM.lambda( "pointwise_wide", inp, merge )
------------
--hsfn = RM.makeHandshake(fn)

harness{ outFile="nilhandshake", fn=fn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H} }
