local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")

W = 128
H = 64

plus100 = d.lift( types.uint(8), types.uint(8) , terra( a : &uint8, out : &uint8  ) @out =  @a+100 end, 1 )

ITYPE = types.array2d( types.uint(8), W, H )
inp = d.input( ITYPE )
out = d.apply( "plus100", d.map( plus100, W, H ), inp )
fn = d.lambda( "pointwise", inp, out )

local Module = fn:compile()

--res:printpretty()
--save(res(load("frame_128.bmp")), "out.bmp")
print("HERE")

terra doit()
  cstdio.printf("DOIT\n")
  var imIn : Im
  imIn:load("frame_128.bmp")
  var imOut : Im
  imOut:load("frame_128.bmp")
  var module : Module
  module:process( [&uint8[W*H]](imIn.data), [&uint8[W*H]](imOut.data) )

  imOut:save("out/pointwise.bmp")
end
doit:printpretty()
print("ROFL")
doit()

doit2 = d.scanlHarness( Module, W*H, "frame_128.bmp", ITYPE,W,H, "out/pointwise2.bmp", ITYPE, W, H)
doit2:printpretty()
doit2()