local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local harness = require "generators.harness"
local harris = require "harris_core"
local C = require "generators.examplescommon"
local f = require "fixed_float"
local G = require "generators.core"

W = 256
H = 256

T = 8

FILTER_FIFO = 128
FILTER_OUTPUT_CNT = 510


----------------
local inp = f.parameter("inp16to8",types.tuple{types.uint(16),types.uint(16)})
local out = f.array2d({inp:index(0):cast(types.uint(8)),inp:index(1):cast(types.uint(8))},2,1)
out = out:disablePipelining()
local touint8pair = out:toRigelModule("touint8pair")
----------------
-- harris -> pos fn
ITYPE = types.array2d(types.uint(8),1)

local inpraw = R.input( types.rv(types.Par(types.array2d(types.bool(),1))) )
local inp = R.apply("ir0", C.index(types.array2d(types.bool(),1),0,0), inpraw)

local PS = RM.posSeq(W,H,1)
local pos = R.apply("posseq", PS, G.ValueToTrigger(inpraw) )
local pos = R.apply("idx0", C.index(PS.outputType:extractData(),0,0), pos )
local pos = R.apply("cst", touint8pair, pos)

local fsinp = R.concat("PTT",{pos,inp})
local out = R.apply("FS",RM.filterSeq(types.array2d(types.uint(8),2),W,H,{FILTER_OUTPUT_CNT,W*H},FILTER_FIFO,false,nil,false),fsinp)
local filterfn = RM.lambda( "filterfnmodule", inpraw, out )

----------------

ITYPE = types.array2d(types.uint(8),T)
OTYPE = types.array2d(types.array2d(types.uint(8),2),T/2)

local inpraw = R.input(R.Handshake(ITYPE))
local inp = R.apply("reducerate", RM.changeRate(types.uint(8),1,8,1), inpraw )
local harrisFn = harris.makeHarris(W,H,true)
local out = R.apply("harrisfilterinst", harrisFn, inp )
local out = R.apply("filt", RM.liftHandshake(RM.liftDecimate(filterfn)), out)
local out = R.apply("AO",RM.makeHandshake(C.arrayop(types.array2d(types.uint(8),2),1,1)),out)
--local out = R.apply("incrate", RM.liftHandshake(RM.changeRate(types.array2d(types.uint(8),2),1,1,4)), out )
fn = RM.lambda( "harris", inpraw, out )

--harness.axi( "harris_filterseq", fn, "box_256.raw", nil, nil, ITYPE, T,W,H, OTYPE,T/2,(W*H)/FILTER_RATE,1)
harness{ outFile="harris_filterseq", fn=fn, inFile="box_256.raw", inSize={W,H}, outSize={FILTER_OUTPUT_CNT,1} }
