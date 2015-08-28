local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")
local harness = require "harness"

W = 128
H = 64
T = 8

inp = S.parameter("inp",types.uint(8))
plus100 = d.lift( "plus100", types.uint(8), types.uint(8) , 10, terra( a : &uint8, out : &uint8  ) @out =  @a+100 end, inp, inp + S.constant(100,types.uint(8)) )

------------
local p100 = d.makeHandshake(d.makeStateful(d.map( plus100, T)))
------------
ITYPE = types.array2d( types.uint(8), T )
local inp = d.input( d.StatefulHandshake(ITYPE) )
local regs = {d.instantiateRegistered("f1",d.fifo(ITYPE,1))}
--local pipelines = {d.applyStore("s1",regs[1],inp)}

------
local pinp = d.applyMethod("l1",regs[1],"load")
local out = d.apply( "plus100", p100, pinp )
--table.insert(pipelines, d.applyStore("s2",regs[2], out))
------
hsfn = d.lambda( "fifo_wide", inp, d.statements{out, d.applyMethod("s1",regs[1],"store",inp)}, regs )
------------

harness.axi( "fifo_wide_handshake_1", hsfn, "frame_128.raw", nil, nil, ITYPE, T,W,H, ITYPE,T,W,H)