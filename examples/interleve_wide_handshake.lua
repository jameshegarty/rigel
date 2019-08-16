local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"
local C = require "generators.examplescommon"

W = 128
H = 64
T = 8

-- this example takes two streams and flattens them into 1

------------
ITYPE = types.array2d( types.uint(8), T )
------------
local BTYPE = types.tuple{ITYPE,types.uint(8)}

local ignoreBin = C.index(BTYPE,0)
------------
--local fifos = { R.instantiateRegistered("f1",RM.fifo(ITYPE,128)), R.instantiateRegistered("f2",RM.fifo(ITYPE,128)) }

A = R.input( R.Handshake(ITYPE) )
local Abroadcast = R.apply("Abroadcast", RM.broadcastStream(types.Par(ITYPE),2), A)

--local AinFifo1 = R.applyMethod("L1", fifos[1],"load")
local AinFifo1 = C.fifo(ITYPE,128)(Abroadcast[0])
B = R.apply( "plus100", RM.makeHandshake(RM.map(C.plus100(types.uint(8)),8)), AinFifo1 )

--local AinFifo2 = R.applyMethod("L2", fifos[2],"load")
AinFifo2 = C.fifo(ITYPE,128)(Abroadcast[1])

local out = R.apply("toHandshakeArray", RM.toHandshakeArrayOneHot(ITYPE,{{1,2},{1,2}}), R.concatArray2d("sa",{AinFifo2,B},2,1))

local SER = RM.sequence( ITYPE, {{1,2},{1,2}}, RM.interleveSchedule( 2, 2 ) ) 
local out = R.apply("ser", SER, out )

out = R.apply("flatten", RM.flattenStreams(ITYPE,{{1,2},{1,2}}), out )

hsfn = RM.lambda( "interleve_wide", A, out )

--harness.axi( "interleve_wide_handshake", hsfn, "frame_128.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W*2,H)
harness{ outFile="interleve_wide_handshake", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W*2,H} }
