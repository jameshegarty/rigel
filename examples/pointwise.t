local d = require "darkroom"
local image = require "image"
local ffi = require("ffi")

W = 128
H = 64

plus100 = d.leaf( terra( out : &uint8, a : &uint8 ) @out =  @a+100 end, darkroom.type.uint(8), d.input( darkroom.type.uint(8) ) )

inp = d.input( darkroom.type.array( darkroom.type.uint(8), {W*H} ) )
out = d.apply( inp, d.map( "plus100",plus100, inp ) )
fn = d.fn( out, inp )

local res = d.compile( fn )
res:printpretty(false)
--save(res(load("frame_128.bmp")), "out.bmp")

terra doit()
  var imIn : Image
  imIn:load("frame_128.bmp")
  var imOut : Image
  imOut:load("frame_128.bmp")

  res( [&uint8[W*H]](imOut.data), [&uint8[W*H]](imIn.data) )
  imOut:save("out/pointwise.bmp")
end

doit()