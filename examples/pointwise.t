local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")

W = 128
H = 64

plus100 = d.lift( types.uint(8), types.uint(8) , terra( a : &uint8, out : &uint8  ) @out =  @a+100 end )

ITYPE = darkroom.Handshake( types.array2d( types.uint(8), W, H ) )
inp = d.input( ITYPE )
out = d.apply( "plus100", d.map( plus100 ), inp )
fn = d.lambda( inp, out )

local res = fn:compile()
res:printpretty()
--save(res(load("frame_128.bmp")), "out.bmp")
print("HERE")

terra doit()
  cstdio.printf("DOIT\n")
  var imIn : Im
  imIn:load("frame_128.bmp")
  var imOut : Im
  imOut:load("frame_128.bmp")

  var inp : ITYPE:toTerraType()
  d.valid(inp) = true
  cstring.memcpy(&d.data(inp), imIn.data, W*H)
  var out : ITYPE:toTerraType()

  res( &inp, &out )
  cstring.memcpy(imOut.data, &d.data(out), W*H)

  imOut:save("out/pointwise.bmp")
end
doit:printpretty()
print("ROFL")
doit()