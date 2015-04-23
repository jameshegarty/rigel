local d = require "darkroom"
local Image = require "image"
local types = require "types"
W = 128
H = 64
T = 1
R = 1
N = R*2+1

-------------
s = d.lift( types.array2d( types.uint(8), N, N ), types.uint(8),
            terra( a : &uint8[N*N], out : &uint8 )
              @out = (@a)[4]
            end,0)

s = d.lift( types.array2d( types.uint(8), 1, N ), types.uint(8),
            terra( a : &uint8[N], out : &uint8 )
              @out = (@a)[0]
            end,0)
-------------
ITYPE = d.Stateful(types.array2d( types.uint(8), T ))
inp = d.input( ITYPE )

convLB = d.apply( "convLB", d.linebuffer( types.uint(8), W,H, T, -N+1, 0, -N+1, 0 ), inp)
convstencils = d.apply( "convstencils", d.makeStateful( d.unpackStencil( types.uint(8), 1, N, T ) ), convLB )
convpipe = d.apply( "shift", d.makeStateful( d.map(s,T)), convstencils )

--convLB = d.apply( "convLB", d.stencilLinebuffer( types.uint(8), W,H, T, -N+1, 0, -N+1, 0 ), inp)
--convstencils = d.apply( "convstencils", d.makeStateful( d.unpackStencil( types.uint(8), N, N, T ) ), convLB )
--convpipe = d.apply( "shift", d.makeStateful( d.map(s,T)), convstencils )


convpipe = d.lambda( "convpipe", inp, convpipe )
-------------

Module = convpipe:compile()
doit = d.scanlHarness( Module, T, "frame_128.bmp", ITYPE,W,H, "out/shift_wide.bmp", ITYPE, W, H)
doit()
