local R = require "rigel"
local RM = require "modules"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"
local RS = require "rigelSimple"
local f = require "fixed_new"
local RHLL = require "rigelhll"

-- (posseq+dramreader) 
-- read image ->
-- merge two & div by two

W = 128
H = 64
T = 8

ITYPE = types.uint(8)

-- {image input, ram read return}
inp = R.input( R.HandshakeTuple{ITYPE,ITYPE}, {{1,1},'x'} )

posseq = RS.connect{ toModule=RS.HS(RM.posSeq(W,H,1)), name="posseqinst" }

--local mergeinp = f.parameter( "inp", types.tuple{ITYPE,types.tuple{types.uint(16),types.uint(16)} } )
--mergefn = (mergeinp:index(0):rshift(4):removeLSBs(4):addMSBs(12)+mergeinp:index(1):index(0))+mergeinp:index(1):index(1):addMSBs(1)
--mergefn = mergefn:removeMSBs(10)
local addr = RHLL.liftMath( function(pos) return (pos:index(0):index(0):addMSBs(9)+(f.constant(H-1):addMSBs(10)-pos:index(0):index(1)):abs()*f.constant(W)):addMSBs(6) end )(posseq)

local a = addr
local b = inp:selectStream(1)
local tub = R.concat("rrtup",{a,b})
--print("TUPL",a,b,tub,a.type,b.type,tub.type)

local ramread = RHLL.readMemory(tub)
  
--merge = RS.connect{ input=RS.fanIn{inp,RS.index{input=posseq,key=0}}, toModule=RS.HS(mergefn:toRigelModule("mergefn")), name="merge" }
local merge = RHLL.liftMath( function(pac) return pac:index(1) end )(RS.fanIn{inp:selectStream(0),ramread:selectStream(0)})
print("MERGETYPE",merge.type,ramread.type)
                     
fn = RM.lambda( "pointwise_wide", inp, R.concat("FIN",{merge,ramread:selectStream(1)}) )
------------
--hsfn = RM.makeHandshake(fn)

harness{ outFile="readmemory_flip", fn=fn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H}, harness=2, inP=1, outP=1, inType=ITYPE, outType=ITYPE, ramType=ITYPE, ramFile="frame_128.raw" }
