local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"
local f = require "fixed"
local C = require "examplescommon"
W = 512
H = 1

-----------------
local inp = f.parameter("highselect", types.uint(8))
local out = inp:gt(f.plainconstant(128,types.uint(8)))
local HS = out:toDarkroom("highselect")

----------------
local inpraw = d.input(types.array2d(types.uint(8),1))
local inp = d.apply("ir0", d.index(types.array2d(types.uint(8),1),0,0), inpraw)

local PS = d.posSeq(W,H,1)
local pos = d.apply("posseq", PS)
local pos = d.apply("idx0", d.index(PS.outputType,0,0), pos )
local pos = d.apply("idx1", d.index(PS.outputType:arrayOver(),0,0), pos )
local pos = d.apply("CST", C.cast(types.uint(16),types.uint(8)), pos)

local filter = d.apply("HS",HS, inp)

--local fsinp = d.apply("PT",d.packTuple{types.uint(8),types.bool()},d.tuple("PTT",{pos,filter},false))
local fsinp = d.tuple("PTT",{pos,filter})
local out = d.apply("FS",d.filterSeq(types.uint(8),W,H,4,8),fsinp)
local filterfn = d.lambda( "filterfn", inpraw, out )
-----------------
local fifos = {}
local statements = {}

T = 8
ITYPE = types.array2d(types.uint(8),T)

local inpraw = d.input(d.Handshake(ITYPE))
local inp = d.apply("reducerate", d.liftHandshake(d.changeRate(types.uint(8),1,8,1)), inpraw )
local out = d.apply("filterfn", d.liftHandshake(d.liftDecimate(filterfn)), inp )
local out = d.apply("AO",d.makeHandshake(C.arrayop(types.uint(8),1,1)),out)
local out = d.apply("incrate", d.liftHandshake(d.changeRate(types.uint(8),1,1,8)), out )
fn = d.lambda( "filterseq", inpraw, out )

harness.axi( "filterseq", fn, "filterseq.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W/4,H)