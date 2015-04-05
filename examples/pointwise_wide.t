local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")

W = 128
H = 64
T = 4

plus100 = d.lift( types.uint(8), types.uint(8) , terra( a : &uint8, out : &uint8  ) @out =  @a+100 end )

ITYPE = darkroom.Handshake( types.array2d( types.uint(8), T ) )
inp = d.input( ITYPE )
out = d.apply( "plus100", d.map( plus100 ), inp )
fn = d.lambda( inp, out )

local res = fn:compile()
res:printpretty()
doit = d.scanlHarness(res, "frame_128.bmp", ITYPE,W,H, "out/pointwise_wide.bmp", ITYPE, W, H)
doit()