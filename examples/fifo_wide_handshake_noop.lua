local R = require "rigel"
local RM = require "generators.modules"
local types = require("types")
local S = require("systolic")
local harness = require "generators.harness"
local C = require "generators.examplescommon"

W = 128
H = 64
T = 8

--inp = S.parameter("inp",types.uint(8))
--plus100 = RM.lift( "plus100", types.uint(8), types.uint(8) , 10, terra( a : &uint8, out : &uint8  ) @out =  @a+100 end, inp, inp + S.constant(100,types.uint(8)) )

------------
local p100 = RM.makeHandshake(RM.map( C.plus100(types.uint(8)), T))
------------
ITYPE = types.array2d( types.uint(8), T )
local inp = R.input( R.Handshake(ITYPE) )
local regs = {R.instantiate("f1",RM.fifo(ITYPE,1,false,W,H,T,true))}

------
local pinp = R.applyMethod("l1",regs[1],"load")
local out = R.apply( "plus100", p100, pinp )
------
hsfn = RM.lambda( "fifo_wide", inp, R.statements{out, R.applyMethod("s1",regs[1],"store",inp)}, regs )
------------

harness{ outFile="fifo_wide_handshake_noop", fn=hsfn, inFile="frame_128.raw", inSize={W,H}, outSize={W,H} }
