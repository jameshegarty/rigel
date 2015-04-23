local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")

W = 128
H = 64
T = 4

plus100 = d.lift( types.uint(8), types.uint(8) , terra( a : &uint8, out : &uint8  ) @out =  @a+100 end, 10 )

------------
inp = d.input( types.uint(8) )
a = d.apply("a", plus100, inp)
b = d.apply("b", plus100, a)
p200 = d.lambda( "p200", inp, b )
------------
ITYPE = types.array2d( types.uint(8), T )
inp = d.input( ITYPE )
out = d.apply( "plus100", d.map( p200, T ), inp )
fn = d.lambda( "pointwise_wide", inp, out )
------------
ITYPE = d.StatefulHandshake(ITYPE)
inp = d.input( ITYPE )
out = d.apply( "hs", d.makeHandshake(d.makeStateful(fn)), inp)
hsfn = d.lambda( "pointwise_wide_hs", inp, out )
------------

--local res, SimState, State = fn:compile()
Module = hsfn:compile()
--res:printpretty()
doit = d.scanlHarnessHandshake( Module, T, "frame_128.bmp", ITYPE,W,H, "out/pointwise_wide_handshake.bmp", ITYPE, W, H)
doit()