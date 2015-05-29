local d = require "darkroom"
local Im = require "image"
local ffi = require("ffi")
local types = require("types")
local S = require("systolic")
local cstdio = terralib.includec("stdio.h")
local cstring = terralib.includec("string.h")

W = 128
H = 64
T = 4

inp = S.parameter("inp",types.uint(8))
plus100 = d.lift( "plus100", types.uint(8), types.uint(8) , 10, terra( a : &uint8, out : &uint8  ) @out =  @a+100 end, inp, inp + S.constant(100,types.uint(8)) )

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
--ITYPE = d.StatefulHandshake(ITYPE)
--inp = d.input( ITYPE )
--out = d.apply( "hs", d.makeHandshake(d.makeStateful(fn)), inp)
--hsfn = d.lambda( "pointwise_wide_hs", inp, out )
hsfn = d.makeHandshake(d.makeStateful(fn))
------------
inp = d.input( d.StatefulHandshake(types.null()) )
out = d.apply("fread",d.makeHandshake(d.freadSeq("frame_128.raw",ITYPE,"../frame_128.raw")),inp)
out = d.apply("pointwise_wide", hsfn, out )
out = d.apply("fwrite", d.makeHandshake(d.fwriteSeq("out/pointwise_wide_handshake.raw",ITYPE,"pointwise_wide_handshake.sim.raw")), out )
top = d.lambda( "top", inp, out )
-------------
f = d.seqMapHandshake( top, W, H, T,2 )
Module = f:compile()
(terra() var m:Module; m:reset(); m:process(nil,nil) end)()

io.output("out/pointwise_wide_handshake.sim.v")
io.write(f:toVerilog())
io.close()

d.writeMetadata("out/pointwise_wide_handshake.metadata.lua",W,H,1,1)

--local res, SimState, State = fn:compile()
--Module = hsfn:compile()
--res:printpretty()
--doit = d.scanlHarnessHandshake( Module, T, "frame_128.bmp", ITYPE,W,H, T,"out/pointwise_wide_handshake.bmp", ITYPE, W, H,0,0,0,0)
--doit()

--io.output("out/pointwise_wide_handshake.v")
--io.write(hsfn:toVerilog())
--io.close()