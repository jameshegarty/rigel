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
local fifos = { R.instantiateRegistered("f1", RM.fifo(ITYPE,128))}

A = R.input( R.Handshake(ITYPE) )

local muxout = R.applyMethod("L1", fifos[1],"load")


local out = R.apply("toHandshakeArray", RM.toHandshakeArrayOneHot(ITYPE,{{1,2},{1,2}}), R.concatArray2d("sa",{A,muxout},2,1))

local SER = RM.serialize( ITYPE, {{1,2},{1,2}}, RM.interleveSchedule( 2, 2 ) ) 
local out = R.apply("ser", SER, out )

multiplexed = R.apply( "plus100", RM.makeHandshake( RM.map(C.plus100(types.uint(8)),8),{{1,2},{1,2}}), out )
local out = R.apply("demux", RM.demux(ITYPE,{{1,2},{1,2}}), multiplexed )


hsfn = RM.lambda( "tmux_wide", A, R.statements{ R.selectStream("i1",out,1), R.applyMethod("s1",fifos[1],"store", R.selectStream("i0",out,0)) }, fifos )

-- b/c this thing has a FIFO in it to recirculate data, it actually finishes earlier than the SDF predicts
-- (in the case of half throughput downstream - where it has time to process data while SDF thinks it would be stalled).
-- This leads to a 2x perf improvement over expected
EARLY_OVERRIDE = 1200

harness{outFile="tmux_wide_handshake", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H}, earlyOverride=EARLY_OVERRIDE}
