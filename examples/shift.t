local d = require "darkroom"
local Image = require "image"
local types = require "types"
W = 128
H = 64
R = 1
N = R*2+1

-------------
s = d.lift( types.array2d( types.uint(8), N, N ), types.uint(8),
            terra( a : &uint8[N*N], out : &uint8 )
              @out = (@a)[8]
            end,0)
-------------
ITYPE = types.array2d( types.uint(8), W,H )
inp = d.input( ITYPE )
convstencils = d.apply(  "convstencils", d.stencil( types.uint(8), W, H, -R,R,-R,R ), inp )
convpipe = d.apply("conv", d.map(s, W,H), convstencils )

convpipe = d.lambda( "convpipe", inp, convpipe )
-------------

Module = convpipe:compile()
doit = d.scanlHarness( Module, W*H, "frame_128.bmp", ITYPE,W,H, "out/shift.bmp", ITYPE, W, H)
doit()
--[=[
terra doit()
  var imIn : Image
  imIn:load("frame_128.bmp")
  var imOut : Image
  imOut:load("frame_128.bmp")

  var module : Module
  module:process( [&uint8[W*H]](imOut.data), [&uint8[W*H]](imIn.data) )
  imOut:save("out/shift.bmp")
end

doit()
]=]