local R = require "rigel"
local RM = require "modules"
local types = require("types")
local S = require("systolic")
local harness = require "harness"
local C = require "examplescommon"

W = 128
H = 64
T = 8

ITYPE = types.array2d( types.uint(8), T )
local inp = R.input( R.Handshake(ITYPE) )
local out = R.apply("ififo", C.fifo(ITYPE,128), inp)
local out = R.apply( "plus100", RM.makeHandshake( RM.map( C.plus100(types.uint(8)), T) ), out )
local out = R.apply("ofifo", C.fifo(ITYPE,128), out)
hsfn = RM.lambda( "fifo_wide", inp, out )
------------

harness{ outFile="fifo_wide_handshake_2_noloop", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H} }
