local R = require "rigel"
local RM = require "modules"
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"
local SDF = require "sdf"
W = 128
H = 64
T = 8

-- this example performs plus100 twice by re-circulating data through the same HW unit

------------
ITYPE = types.array2d( types.uint(8), T )
------------
local fifos = { R.instantiate("f1", RM.fifo( ITYPE, 128, nil, nil, nil, nil, nil, nil, SDF{1,2}) ) } --, {{1,2}}) }

A = R.input( R.Handshake(ITYPE), {{1,2}} )

local muxout = R.applyMethod("L1", fifos[1],"load")

local out = R.apply("toHandshakeArray", RM.toHandshakeArrayOneHot(ITYPE,{{1,2},{1,2}}), R.concatArray2d("sa",{A,muxout},2,1))

local SER = RM.serialize( ITYPE, {{1,2},{1,2}}, RM.interleveSchedule( 2, 2 ) ) 
local out = R.apply("ser", SER, out )

multiplexed = R.apply( "plus100", RM.makeHandshake( RM.map(C.plus100(types.uint(8)),8),{{1,2},{1,2}}), out )
local out = R.apply("demux", RM.demux(ITYPE,{{1,2},{1,2}}), multiplexed )

local FIFOSTORE = R.applyMethod("s1",fifos[1],"store", R.selectStream("i0",out,0))
hsfn = RM.lambda( "tmux_wide", A, R.statements{ R.selectStream("i1",out,1), FIFOSTORE }, fifos )

-- b/c this thing has a FIFO in it to recirculate data, it actually finishes earlier than the SDF predicts
-- (in the case of half throughput downstream - where it has time to process data while SDF thinks it would be stalled).
-- This leads to a 2x perf improvement over expected
EARLY_OVERRIDE = 1200

harness{outFile="tmux_wide_handshake", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H}, earlyOverride=EARLY_OVERRIDE}
