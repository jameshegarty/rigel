local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"
local C = require "generators.examplescommon"

R.AUTO_FIFOS = false

W = 128
H = 64
T = 8

------------
local p100 = RM.makeHandshake( RM.map( C.plus100(types.uint(8)), T) )
------------
ITYPE = types.array2d( types.uint(8), T )
local inp = R.input( R.Handshake(ITYPE) )
local regs = {R.instantiate("f1", RM.fifo(ITYPE,128)), R.instantiate("f2", RM.fifo(ITYPE,128)) }
------
local pinp = R.applyMethod("l1",regs[1],"load")
local out = R.apply( "plus100", p100, pinp )
------
hsfn = RM.lambda( "fifo_wide", inp, R.statements{ R.applyMethod("l2",regs[2],"load"), R.applyMethod("s1",regs[1],"store",inp), R.applyMethod("s2",regs[2], "store",out)}, regs )
------------

harness{ outFile="fifo_wide_handshake_2", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H} }
