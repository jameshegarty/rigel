local d = require "darkroom"
local Image = require "image"
local types = require("types")
local S = require("systolic")

T = 8 -- throughput
--ConvRadius = 1
ConvWidth = 4
ConvArea = math.pow(ConvWidth,2)

inputW = 128
inputH = 64

-- expand to include crop region
W = upToNearest(T,128+ConvWidth-1)
H = 64+ConvWidth-1

WW = upToNearest(T,W+ConvWidth-1)
HH = H+ConvWidth-1

BASE_TYPE = types.array2d( types.uint(8), T )

hsfn = d.compose("HSFN",
                 d.liftHandshake(d.padSeq(types.uint(8), W, H, T, (WW-W), 0, (HH-H), 0, 128)),
                 d.liftHandshake(d.padSeq(types.uint(8), inputW, inputH, T, (W-inputW), 0, (H-inputH), 0, 0)) )

inp = d.input( d.StatefulHandshake(types.null()) )
out = d.apply("fread",d.makeHandshake(d.freadSeq("frame_128.raw",BASE_TYPE,"../frame_128.raw")),inp)
out = d.apply("pad", hsfn, out )
out = d.apply("fwrite", d.makeHandshake(d.fwriteSeq("out/pad2_wide_handshake.raw",BASE_TYPE,"pad2_wide_handshake.sim.raw")), out )
harness = d.lambda( "harness", inp, out )
-------------
f = d.seqMapHandshake( harness, inputW, inputH, WW, HH, T,false,4 )
Module = f:compile()
(terra() var m:Module; m:reset(); m:process(nil,nil) end)()

io.output("out/pad2_wide_handshake.sim.v")
io.write(f:toVerilog())
io.close()
----------
fnaxi = d.seqMapHandshake( hsfn, inputW, inputH, WW, HH,T, true )
io.output("out/pad2_wide_handshake.axi.v")
io.write(fnaxi:toVerilog())
io.close()
--------
d.writeMetadata("out/pad2_wide_handshake.metadata.lua",WW,HH,1,1,"frame_128.raw")

