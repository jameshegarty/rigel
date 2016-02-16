local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
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
local touint8pair = out:toDarkroom("touint8pair")
----------------
-- harris -> pos fn
ITYPE = types.array2d(types.uint(8),1)

local inpraw = d.input(types.array2d(types.bool(),1))
local inp = d.apply("ir0", d.index(types.array2d(types.bool(),1),0,0), inpraw)

local PS = d.posSeq(W,H,1)
local pos = d.apply("posseq", PS)
local pos = d.apply("idx0", d.index(PS.outputType,0,0), pos )
--local pos = d.apply("idx1", d.index(PS.outputType:arrayOver(),0,0), pos )
local pos = d.apply("cst", touint8pair, pos)
--local pos = d.apply("CST", C.cast(types.uint(16),types.uint(8)), pos)

--local fsinp = d.apply("PT",d.packTuple{types.uint(8),types.bool()},d.tuple("PTT",{pos,filter},false))
local fsinp = d.tuple("PTT",{pos,inp})
local out = d.apply("FS",d.filterSeq(types.array2d(types.uint(8),2),W,H,FILTER_RATE,FILTER_FIFO),fsinp)
local filterfn = d.lambda( "filterfn", inpraw, out )

----------------

ITYPE = types.array2d(types.uint(8),T)
OTYPE = types.array2d(types.array2d(types.uint(8),2),T/2)

local inpraw = d.input(d.Handshake(ITYPE))
local inp = d.apply("reducerate", d.liftHandshake(d.changeRate(types.uint(8),1,8,1)), inpraw )
local harrisFn = harris.makeHarris(W,H,true)
local out = d.apply("filterfn", harrisFn, inp )
local out = d.apply("filt", d.liftHandshake(d.liftDecimate(filterfn)), out)
local out = d.apply("AO",d.makeHandshake(C.arrayop(types.array2d(types.uint(8),2),1,1)),out)
local out = d.apply("incrate", d.liftHandshake(d.changeRate(types.array2d(types.uint(8),2),1,1,4)), out )
fn = d.lambda( "harris", inpraw, out )

harness.axi( "harris_filterseq", fn, "box_256.raw", nil, nil, ITYPE, T,W,H, OTYPE,T/2,(W*H)/FILTER_RATE,1)