local R = require "rigel"
local RM = require "modules"
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"

W = 128
H = 64
T = 8

--inp = S.parameter("inp",types.uint(8))
--plus100 = RM.lift( "plus100", types.uint(8), types.uint(8) , 10, terra( a : &uint8, out : &uint8  ) @out =  @a+100 end, inp, inp + S.constant(100,types.uint(8)) )
------------
ITYPE = types.array2d( types.uint(8), T )
------------
local BTYPE = types.tuple{ITYPE,types.uint(8)}
--inp = S.parameter("inp",BTYPE)
--ignoreBin = RM.lift( "ignoreBin", BTYPE, ITYPE, 0, terra( a:&BTYPE:toTerraType(), out:&ITYPE:toTerraType()) @out = a._0 end, inp, S.index(inp,0) )
local ignoreBin = C.index(BTYPE,0)
------------
local fifos = { R.instantiateRegistered("f1",RM.fifo(ITYPE,128)), R.instantiateRegistered("f2",RM.fifo(ITYPE,128)) }

A = R.input( R.Handshake(ITYPE) )
local Abroadcast = R.apply("Abroadcast", RM.broadcastStream(ITYPE,2), A)

local AinFifo1 = R.applyMethod("L1", fifos[1],"load")
B = R.apply( "plus100", RM.makeHandshake(RM.map(C.plus100(types.uint(8)),8)), AinFifo1 )



local AinFifo2 = R.applyMethod("L2", fifos[2],"load")

local out = R.apply("toHandshakeArray", RM.toHandshakeArrayOneHot(ITYPE,{{1,2},{1,2}}), R.concatArray2d("sa",{AinFifo2,B},2,1))

local SER = RM.serialize( ITYPE, {{1,2},{1,2}}, RM.interleveSchedule( 2, 2 ) ) 
local out = R.apply("ser", SER, out )

out = R.apply("flatten", RM.flattenStreams(ITYPE,{{1,2},{1,2}}), out )

hsfn = RM.lambda( "interleve_wide", A, R.statements{out, R.applyMethod("s1",fifos[1],"store",R.selectStream("A0",Abroadcast,0)), R.applyMethod("s2",fifos[2],"store",R.selectStream("A1",Abroadcast,1)) }, fifos )

--harness.axi( "interleve_wide_handshake", hsfn, "frame_128.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W*2,H)
harness{ outFile="interleve_wide_handshake", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W*2,H} }
