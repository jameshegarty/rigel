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

p100 = S.moduleConstructor( "plus100" )
inp = S.parameter("process_input",types.uint(8))
process = p100:addFunction( S.lambda( "process", inp, inp + S.constant( 100, types.uint(8) ), "process_output" ) )

plus100 = d.lift( types.uint(8), types.uint(8) , 10, terra( a : &uint8, out : &uint8  ) @out =  @a+100 end, p100 )

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
-------------
inp = d.input( d.Stateful(types.null()) )
out = d.apply("fread",d.freadSeq("frame_128.raw",ITYPE,"../frame_128.raw"),inp)
out = d.apply("pointwise_wide",d.makeStateful(fn),out)
out = d.apply("fwrite",d.fwriteSeq("out/pointwise_wide.raw",ITYPE,"pointwise_wide.sim.raw"),out)
top = d.lambda( "top", inp, out )
-------------
f = d.seqMap( top, W, H, T )
Module = f:compile()
(terra() var m:Module; m:reset(); m:process(nil,nil) end)()

io.output("out/pointwise_wide.sim.v")
io.write(f:toVerilog())
io.close()

--local res, SimState, State = fn:compile()
--Module = fn:compile()
--res:printpretty()
--doit = d.scanlHarness( Module, T, "frame_128.bmp", ITYPE,W,H, T,"out/pointwise_wide.bmp", ITYPE, W, H,0,0,0,0)
--doit()

--io.output("out/pointwise_wide.v")
--io.write(fn:toVerilog())
--io.close()