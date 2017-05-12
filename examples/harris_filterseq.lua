local R = require "rigel"
local RM = require "modules"
local types = require("types")
local harness = require "harness"
local harris = require "harris_core"
local C = require "examplescommon"
local f = require "fixed_float"

W = 256
H = 256

T = 8

FILTER_FIFO = 128
FILTER_RATE = 128


----------------
local inp = f.parameter("inp16to8",types.tuple{types.uint(16),types.uint(16)})
local out = f.array2d({inp:index(0):cast(types.uint(8)),inp:index(1):cast(types.uint(8))},2,1)
local touint8pair = out:toRigelModule("touint8pair")
----------------
-- harris -> pos fn
ITYPE = types.array2d(types.uint(8),1)

local inpraw = R.input(types.array2d(types.bool(),1))
local inp = R.apply("ir0", C.index(types.array2d(types.bool(),1),0,0), inpraw)

local PS = RM.posSeq(W,H,1)
local pos = R.apply("posseq", PS)
local pos = R.apply("idx0", C.index(PS.outputType,0,0), pos )
local pos = R.apply("cst", touint8pair, pos)

local fsinp = R.tuple("PTT",{pos,inp})
local out = R.apply("FS",RM.filterSeq(types.array2d(types.uint(8),2),W,H,{1,FILTER_RATE},FILTER_FIFO),fsinp)
local filterfn = RM.lambda( "filterfnmodule", inpraw, out )

----------------

ITYPE = types.array2d(types.uint(8),T)
OTYPE = types.array2d(types.array2d(types.uint(8),2),T/2)

local inpraw = R.input(R.Handshake(ITYPE))
local inp = R.apply("reducerate", RM.liftHandshake(RM.changeRate(types.uint(8),1,8,1)), inpraw )
local harrisFn = harris.makeHarris(W,H,true)
local out = R.apply("harrisfilterinst", harrisFn, inp )
local out = R.apply("filt", RM.liftHandshake(RM.liftDecimate(filterfn)), out)
local out = R.apply("AO",RM.makeHandshake(C.arrayop(types.array2d(types.uint(8),2),1,1)),out)
local out = R.apply("incrate", RM.liftHandshake(RM.changeRate(types.array2d(types.uint(8),2),1,1,4)), out )
fn = RM.lambda( "harris", inpraw, out )

--harness.axi( "harris_filterseq", fn, "box_256.raw", nil, nil, ITYPE, T,W,H, OTYPE,T/2,(W*H)/FILTER_RATE,1)
harness{ outFile="harris_filterseq", fn=fn, inFile="box_256.raw", inSize={W,H}, outSize={(W*H)/FILTER_RATE,1} }
