local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local harness = require "generators.harness"
local f = require "fixed"
local C = require "generators.examplescommon"
local G = require "generators.core"

W = 512
H = 1

-----------------
local inp = f.parameter("highselect", types.uint(8))
local out = inp:gt(f.plainconstant(128,types.uint(8))):disablePipelining()
local HS = out:toRigelModule("highselect")

----------------
local inpraw = R.input(types.rv(types.Par(types.array2d(types.uint(8),1))))
local inp = R.apply("ir0", C.index(types.array2d(types.uint(8),1),0,0), inpraw)

local PS = RM.posSeq(W,H,1)
local pos = R.apply("posseq", PS, G.ValueToTrigger(inpraw))
local pos = R.apply("idx0", C.index(PS.outputType:lower(),0,0), pos )
local pos = R.apply("idx1", C.index(PS.outputType:lower():arrayOver(),0,0), pos )
local pos = R.apply("CST", C.cast(types.uint(16),types.uint(8)), pos)

local filter = R.apply("HS",HS, inp)

local fsinp = R.concat("PTT",{pos,filter})
local out = R.apply("FS",RM.filterSeq(types.uint(8),W,H,{1,4},8,nil,nil,false),fsinp)
local filterfn = RM.lambda( "filterfn", inpraw, out )
-----------------
local fifos = {}
local statements = {}

T = 8
ITYPE = types.array2d(types.uint(8),T)

local inpraw = R.input(R.Handshake(ITYPE))
local inp = R.apply("reducerate", RM.changeRate(types.uint(8),1,8,1), inpraw )
local out = R.apply("filterfn", RM.liftHandshake(RM.liftDecimate(filterfn)), inp )
local out = R.apply("AO",RM.makeHandshake(C.arrayop(types.uint(8),1,1)),out)
local out = R.apply("incrate", RM.changeRate(types.uint(8),1,1,8), out )
fn = RM.lambda( "filterseq", inpraw, out )

--harness.axi( "filterseq", fn, "filterseq.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W/4,H)
harness{ outFile="filterseq", fn=fn, inFile="filterseq.raw", inSize={W,H}, outSize={W/4,H} }
