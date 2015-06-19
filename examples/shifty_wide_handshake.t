local d = require "darkroom"
local Image = require "image"
local types = require "types"
W = 128
H = 64
T = 8

-------------
RAWTYPE = types.array2d( types.uint(8), T )
ITYPE = d.Stateful(RAWTYPE)
inp = d.input( ITYPE )
convLB = d.apply( "convLB", d.linebuffer( types.uint(8), W,H, T, -1 ), inp)
convpipe = d.apply( "slice", d.makeStateful(d.slice( types.array2d(types.uint(8),T,2), 0, T-1, 0, 0 ) ), convLB)
convpipe = d.lambda( "convpipe", inp, convpipe )

------------
inp = d.input( d.StatefulHandshake(types.null()) )
out = d.apply("fread",d.makeHandshake(d.freadSeq("frame_128.raw",RAWTYPE,"../frame_128.raw")),inp)
hsfn = d.makeHandshake(convpipe)
out = d.apply("shifty_wide", hsfn, out )
out = d.apply("fwrite", d.makeHandshake(d.fwriteSeq("out/shifty_wide_handshake.raw",RAWTYPE,"shifty_wide_handshake.sim.raw")), out )
top = d.lambda( "top", inp, out )
-------------
f = d.seqMapHandshake( top, W, H, W,H, T, false, 2 )
Module = f:compile()
(terra() var m:Module; m:reset(); m:process(nil,nil) end)()

io.output("out/shifty_wide_handshake.sim.v")
io.write(f:toVerilog())
io.close()
----------
fnaxi = d.seqMapHandshake( hsfn, W, H, W,H, T, true )
io.output("out/shifty_wide_handshake.axi.v")
io.write(fnaxi:toVerilog())
io.close()
--------
d.writeMetadata("out/shifty_wide_handshake.metadata.lua",W,H,1,1,"frame_128.raw")
