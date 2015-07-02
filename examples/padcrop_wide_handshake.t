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


BASE_TYPE = types.array2d( types.uint(8), T )

hsfn = d.compose("HSFN",
                 d.liftHandshake(d.liftDecimate(d.cropSeq(types.uint(8), W, H, T, 0, (W-inputW), 0, (H-inputH), 0))),
                 d.liftHandshake(d.padSeq(types.uint(8), inputW, inputH, T, (W-inputW), 0, (H-inputH), 0, 128)) )
--------------
function harness(infile,outfile,id)
local inp = d.input( d.StatefulHandshake(types.null()) )
local out = d.apply("fread",d.makeHandshake(d.freadSeq(infile,BASE_TYPE)),inp)
out = d.apply("pad", hsfn, out )
out = d.apply("fwrite", d.makeHandshake(d.fwriteSeq(outfile,BASE_TYPE)), out )
return d.lambda( "harness"..id, inp, out )
end
-------------
f = d.seqMapHandshake( harness("frame_128.raw","padcrop_wide_handshake.raw",1), inputW, inputH, T, inputW, inputH, T,false,4 )
Module = f:compile()
(terra() var m:Module; m:reset(); m:process(nil,nil) end)()

--------
f = d.seqMapHandshake( harness("../../frame_128.raw","padcrop_wide_handshake.sim.raw",2), inputW, inputH, T, inputW, inputH, T,false )
io.output("out/padcrop_wide_handshake.sim.v")
io.write(f:toVerilog())
io.close()
--------
f = d.seqMapHandshake( harness("../../frame_128.raw","padcrop_wide_handshake_half.sim.raw",3), inputW, inputH, T, inputW, inputH, T,false, 2 )
io.output("out/padcrop_wide_handshake_half.sim.v")
io.write(f:toVerilog())
io.close()
----------
fnaxi = d.seqMapHandshake( hsfn, inputW, inputH, T, inputW, inputH,T, true )
io.output("out/padcrop_wide_handshake.axi.v")
io.write(fnaxi:toVerilog())
io.close()
--------
d.writeMetadata("out/padcrop_wide_handshake.metadata.lua",inputW,inputH,1,1,"frame_128.raw")
d.writeMetadata("out/padcrop_wide_handshake_half.metadata.lua",inputW,inputH,1,1,"frame_128.raw")

